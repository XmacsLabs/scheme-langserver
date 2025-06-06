(library (scheme-langserver protocol apis document-symbol)
  (export 
    document-symbol)
  (import 
    (chezscheme) 

    (scheme-langserver analysis workspace)
    (scheme-langserver analysis identifier reference)

    (scheme-langserver protocol alist-access-object)

    (scheme-langserver util association)
    (scheme-langserver util path) 
    (scheme-langserver util io)
    (scheme-langserver util dedupe) 

    (scheme-langserver virtual-file-system index-node)
    (scheme-langserver virtual-file-system document)
    (scheme-langserver virtual-file-system file-node))

; https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#documentSymbol
(define (document-symbol workspace params)
  (let* ([text-document (alist->text-document (assq-ref params 'textDocument))]
      ;why pre-file-node? because many LSP clients, they wrongly produce uri without processing escape character, and here I refer
      ;https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#uri
      [pre-file-node (walk-file (workspace-file-node workspace) (uri->path (text-document-uri text-document)))]
      [file-node (if (null? pre-file-node) (walk-file (workspace-file-node workspace) (substring (text-document-uri text-document) 7 (string-length (text-document-uri text-document)))) pre-file-node)]
      [document (file-node-document file-node)])
    (refresh-workspace-for workspace file-node)
    (let* ([index-node-list (document-index-node-list document)]
         [identifiers
          (filter 
            (lambda (identifier-reference)
              (equal? document (identifier-reference-document identifier-reference)))
            (apply append 
              (map 
                index-node-references-import-in-this-node
                index-node-list)))]
        [deduped-identifiers
          (dedupe 
            identifiers
            (lambda (ref1 ref2)
              (and 
                (eq? (identifier-reference-identifier ref1)
                    (identifier-reference-identifier ref2))
                (let ([node1 (identifier-reference-index-node ref1)]
                      [node2 (identifier-reference-index-node ref2)])
                  (and 
                    (equal? (index-node-start node1) (index-node-start node2))
                    (equal? (index-node-end node1) (index-node-end node2)))))))])
      (let ([result-vector 
             (list->vector 
               (map document-symbol->alist 
                 (map identifier->document-symbol deduped-identifiers)))])
        result-vector))))

(define (identifier->document-symbol identifier)
  (let* ([document (identifier-reference-document identifier)]
      [text (document-text document)]
      [index-node (identifier-reference-index-node identifier)]
      [name (symbol->string (identifier-reference-identifier identifier))]
      [start-position (apply make-position (document+bias->position-list document (index-node-start index-node)))]
      [end-position (apply make-position (document+bias->position-list document (index-node-end index-node)))]
      [range (make-range start-position end-position)])
    (make-document-symbol 
      name
; https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#symbolKind
; todo: type inference
      13
      range
      range)))
)
