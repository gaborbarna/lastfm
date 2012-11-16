#lang racket
(require net/url)
(require xml)
(require xml/path)
(require openssl/sha1)
(require racket/fasl)

(define cache-dir "/home/lesbroot/etc/cache/")
(define api-url "http://ws.audioscrobbler.com/2.0/")
(define api-key (cons 'api_key "79307c3a527388d5c47a44c63ddf2a46"))
(define method-info (cons 'method "artist.getinfo"))
(define method-similar (cons 'method "artist.getsimilar"))
(define artists '("Portishead" "Emancipator" "Dirty Elegance"))

(define-syntax-rule (url-param pair)
  (let ([name (symbol->string (car pair))])
    (string-append name "=" (cdr pair))))

(define url-string
  (case-lambda
    [(url) url]
    [(url param0 . param-rest)
     (string-append* url "?" (url-param param0)
                     (map (lambda(x) (string-append "&" (url-param x)))
                          param-rest))]))

(define (fetch-xml artist method)
  (let* ([url (string->url (url-string
                            api-url api-key method (cons 'artist artist)))]
         [in (get-pure-port url)]
         [xexpression (xml->xexpr (document-element (read-xml in)))])
    (close-input-port in)
    xexpression))

(define (request-rest artist)
  (let* ([summary (se-path* '(summary) (fetch-xml artist method-info))]
         [artists (se-path*/list '(similarartists)
                                 (fetch-xml artist method-similar))]
         [similar (map (lambda (x) (string-append* (se-path*/list '(name) x)))
                       artists)])
    (cons (xexpr->string summary)
          (filter (lambda (x) (not (equal? x ""))) similar))))

(define (consumer)
  (define (write-to-file msg path)
    (let ([out (open-output-file path)])
      (s-exp->fasl msg out)
      (close-output-port out)))
  (define (loop)
    (let ([msg (thread-receive)])
      (cond [(eq? msg 'kill) 'bye]
            [else (begin (cond [(not (eq? (first msg) #f))
                                (write-to-file (rest msg) (first msg))])
                         (display-message (rest msg))
                         (newline)
                         (loop))])))
  (loop))

(define (display-message msg)
  (displayln (first msg))
  (displayln (take (rest msg) 6)))

(define (read-from-file path)
  (let* ([in (open-input-file path)]
         [info (fasl->s-exp in)])
    (close-input-port in)
    info))

(define (run artist msg-consumer)
  (lambda ()
    (let* ([hash-artist (sha1 (open-input-string artist))]
           [path (string-append cache-dir hash-artist)])
      (cond [(file-exists? path)
             (thread-send msg-consumer (cons #f (read-from-file path)))]
            [else
             (thread-send msg-consumer (cons path (request-rest artist)))]))))

(define (main)
  (let ([msg-consumer (thread consumer)])
    (define (create-threads artists threads)
      (cond [(null? artists) threads]
            [else
             (let ([thunk (run (first artists) msg-consumer)])
               (create-threads (rest artists) (cons (thread thunk) threads)))]))
    (let ([threads (create-threads artists '())])
      (for ([thread threads])
           (thread-wait thread)))
    (thread-send msg-consumer 'kill)
    (thread-wait msg-consumer)))

(main)
