(library (scheme-langserver analysis type substitutions rules record)
  (export define-record-type-process)
  (import 
    (chezscheme) 
    (ufo-match)

    (scheme-langserver util cartesian-product)
    (ufo-try)
    (scheme-langserver util sub-list)

    (scheme-langserver analysis identifier reference)
    (scheme-langserver analysis identifier meta)
    (scheme-langserver analysis type substitutions util)

    (scheme-langserver virtual-file-system index-node)
    (scheme-langserver virtual-file-system document))

(define (define-record-type-process document index-node)
  (let* ([ann (index-node-datum/annotations index-node)]
      [expression (annotation-stripped ann)]
      [children (index-node-children index-node)])
    (match expression
      [(_ dummy0 dummy1 ...) 
        (let ([collection (private-collect-identifiers index-node)])
          (if (null? collection)
            '()
            (let* ([predicator (find (lambda (identifier) (equal? (identifier-reference-type identifier) 'predicator)) collection)]
                [constructor (find (lambda (identifier) (equal? (identifier-reference-type identifier) 'constructor)) collection)]
                [getters (filter (lambda (identifier) (equal? (identifier-reference-type identifier) 'getter)) collection)]
                [setters (filter (lambda (identifier) (equal? (identifier-reference-type identifier) 'setter)) collection)])
              (if (and predicator constructor)
                (if (null? (identifier-reference-type-expressions predicator))
                  (begin
                    (map 
                      (lambda (getter)
                        (identifier-reference-type-expressions-set! 
                          getter
                          `((something? <- (inner:list? ,predicator)))))
                      getters)
                    (map 
                      (lambda (setter)
                        (identifier-reference-type-expressions-set! 
                          setter
                          `((void? <- (inner:list? ,predicator something?)))))
                      setters)
                    (identifier-reference-type-expressions-set! 
                      predicator
                      `((,(construct-type-expression-with-meta 'boolean?) <- (inner:list? something?))))
                    (identifier-reference-type-expressions-set! 
                      constructor 
                      `((,predicator <- (inner:list? something? ...)))))))))
            '())]
      [else '()])))

(define (private-collect-identifiers index-node)
  (if (null? (index-node-references-export-to-other-node index-node))
    (apply append (map private-collect-identifiers (index-node-children index-node)))
    (index-node-references-export-to-other-node index-node)))
)