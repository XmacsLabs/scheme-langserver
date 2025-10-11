(library (scheme-langserver protocol analysis request-queue)
  (export 
    make-request-queue
    request-queue-pop
    request-queue-push
    without-mutex:leisure?)
  (import 
    (chezscheme)
    (slib queue)

    (scheme-langserver util association)
    (scheme-langserver protocol request)
    (scheme-langserver analysis workspace))

(define-record-type request-queue 
  (fields 
    (immutable mutex)
    (immutable condition)
    (immutable queue)
    (mutable tickal-task-list))
  (protocol
    (lambda (new)
      (lambda ()
        (new (make-mutex) (make-condition) (make-queue) '())))))

(define ticks 10000)

(define-record-type tickal-task 
  (fields 
    (immutable request)
    (immutable request-queue)
    (mutable stop?)
    (mutable expire)
    (mutable complete))
  (protocol
    ;must have request-queue-mutex
    (lambda (new)
      (lambda (request request-queue workspace)
        (letrec* ([new-task (new request request-queue #f '() '())]
            [complete 
              (lambda (ticks value) 
                (remove:from-request-tickal-task-list request-queue new-task)
                value)]
            [expire 
              (lambda (remains) 
                (if (tickal-task-stop? new-task)
                  (with-mutex (workspace-mutex workspace)
                    (remove:from-request-tickal-task-list request-queue new-task))
                  (remains ticks (tickal-task-complete new-task) (tickal-task-expire new-task))))])
          (enqueue! (request-queue-queue request-queue) new-task)
          (request-queue-tickal-task-list-set! 
            request-queue
            `(,@(request-queue-tickal-task-list request-queue) ,new-task))

          (tickal-task-expire-set! new-task expire)
          (tickal-task-complete-set! new-task complete)

          new-task)))))

(define (request-queue-pop queue request-processor)
  (with-mutex (request-queue-mutex queue)
      (if (queue-empty? (request-queue-queue queue))
        ;by default, this will release request-queue-mutex 
        ;and re-enter when request-queue-condition is signed.
        (condition-wait (request-queue-condition queue) (request-queue-mutex queue)))
      (letrec* ([task (dequeue! (request-queue-queue queue))]
          [request (tickal-task-request task)]
          [job (lambda () (request-processor request))])
        ;will be in another thread
        (lambda () ((make-engine job) ticks (tickal-task-complete task) (tickal-task-expire task))))))

(define (remove:from-request-tickal-task-list queue task)
  (with-mutex (request-queue-mutex queue)
    (request-queue-tickal-task-list-set! 
      queue
      (remove task (request-queue-tickal-task-list queue)))))

(define (without-mutex:leisure? queue)
  (and (queue-empty? (request-queue-queue queue)) (null? (request-queue-tickal-task-list queue))))

(define (request-queue-push queue request potential-request-processor workspace)
  (with-mutex (request-queue-mutex queue)
    (case (request-method request)
      ["$/cancelRequest"
        (let* ([id (assq-ref (request-params request) 'id)]
            [pure-queue (request-queue-queue queue)]
            ;here, id is cancel target id
            [predicator (lambda (task) (equal? id (request-id (tickal-task-request task))))]
            [tickal-task (find predicator (request-queue-tickal-task-list queue))])
          ;must cancel in local thread.
          (when tickal-task 
            (tickal-task-stop?-set! tickal-task #t)
            (potential-request-processor 
              (make-request id "$/cancelRequest" (make-alist 'method (request-method (tickal-task-request tickal-task)))))))]
      [else (make-tickal-task request queue workspace)])
      ;because the pool is limited to have only one thread.
    (condition-signal (request-queue-condition queue))))
)
