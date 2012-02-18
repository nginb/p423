;; uncover-register-conflict.ss
;;
;; part of p423-sp12/srwaggon-p423 a4
;; http://github.iu.edu/p423-sp12/srwaggon-p423
;;
;; Samuel Waggoner
;; srwaggon@indiana.edu
;; 2012 / 2 / 15

#!chezscheme
(library (compiler uncover-register-conflict)
  (export uncover-register-conflict)
  (import
   ;; Load Chez Scheme primitives:
   (chezscheme)
   ;; Load compiler framework:
   (framework match)
   (framework helpers)
   (compiler helpers))

#|
uncover-register-conflict takes the blankets away from
register conflicts so that they freeze to death and die.
|# 
(define-who (uncover-register-conflict program)
  
  ;; graph-add! : symbol symbol conflict-graph --> conflict-graph
  ;; graph-add! side-effects the given conflict-graph by set-cdr!'ing
  ;; the given symbol's association's cdr as the set-cons of its current
  ;; cdr and the given conflicting (second) symbol.
  (define (graph-add! s conflict graph)
    (when (uvar? s)
      (let ([assoc (assq s graph)])
        (if assoc
            (set-cdr! assoc (set-cons conflict (cdr assoc)))
            (cons (list s conflict) graph))))
    graph)

  ;; update-graph : symbol live-set conflict-graph --> conflict-graph
  (define (update-graph s conflicts graph)
    (let loop ([conflicts conflicts][graph graph])
      (cond
        [(null? conflicts) graph]
        [else (loop (cdr conflicts)
                    (graph-add! (car conflicts) s (graph-add! s (car conflicts) graph)))])))

  ;; iterate across each mem of conflicts and 
                  
  ;; handle-var : symbol live-set --> live-set
  ;; iff the var is a uvar or a register it is added
  ;; to the live-set before the live-set is returned.
  (define (handle-var var ls)
    (if (or (uvar? var) (register? var)) (set-cons var ls) ls))

  ;; Effect : Effect* Effect conflict-graph live-set --> conflict-graph live-set
  (define (Effect effect* effect graph live)
    (match effect
      [(nop) (Effect* effect* graph live)]
      [(set! ,lhs (,binop ,rhs0 ,rhs1))
       (let ([ls (remove lhs live)])
         (Effect* effect* (update-graph lhs ls graph) (handle-var rhs0 (handle-var rhs1 ls))))]
      [(set! ,lhs ,rhs)
       (let ([ls (remove lhs live)])
         (Effect* effect* (update-graph lhs ls graph) (handle-var rhs ls)))]
      [(if ,pred ,conseq ,altern)
       (let*-values ([(ga lsa) (Effect '() altern graph live)]
                     [(gc lsc) (Effect '() conseq graph live)]
                     [(gp lsp) (Pred pred graph lsc lsa)])
         (Effect* effect* gp lsp))]
      [(begin ,e* ...) (Effect* (append e* effect*) graph live)]
      [,else (invalid who 'Effect else)]))

  ;; Effect* : Effect* conflict-graph live-set --> conflict-graph live-set
  (define (Effect* effect* graph live)
    (match effect*
      [() (values graph live)]
      [(,effect* ... ,effect) (Effect effect* effect graph live)]
      [,else (invalid who 'Effect* else)]))

  ;; Pred : Pred conflict-graph live-set --> conflict-graph live-set
  (define (Pred pred graph Clive Alive)
    (match pred
      [(true) (values graph Clive)]
      [(false) (values graph Alive)]
      [(begin ,effect* ... ,pred)
       (let*-values ([(gp lsp) (Pred pred graph Clive Alive)]
                     [(ge* lse*) (Effect* effect* gp lsp)])
         (values ge* lse*))]
      [(if ,pred ,conseq ,altern)
       (let*-values ([(ga lsa) (Pred altern graph Clive Alive)]
                     [(gc lsc) (Pred conseq graph Clive Alive)]
                     [(gp lsp) (Pred pred graph lsc lsa)])
         (values graph (union lsp lsc lsa)))]
      [(,relop ,triv0 ,triv1)
       (values graph (handle-var triv0 (handle-var triv1 (union Clive Alive))))]
      [,else (invalid who 'Pred else)]))

  ;; Tail : Tail conflict-graph live-set --> conflict-graph live-set
  (define (Tail tail graph live)
    (match tail
      [(begin ,effect* ... ,tail)
       (let*-values ([(gt lst) (Tail tail graph live)]
                     [(ge* lse*) (Effect* effect* gt lst)])
         (values graph (union lst lse*)))]
      [(if ,pred ,conseq ,altern)
       (let*-values ([(ga lsa) (Tail altern graph live)]
                     [(gc lsc) (Tail conseq graph live)]
                     [(gp lsp) (Pred pred graph lsc lsa)])
         (values graph (union lsp lsc lsa)))]
      [(,triv ,loc* ...) (values graph (handle-var triv (union loc* live)))]
      [,else (invalid who 'Tail else)]))

  (define (Body body) ;; Body --> Body
    (match body
      [(locals ,uvar* ,tail)
       (let*-values ([(empty-graph) (map (lambda (s) (cons s '())) uvar*)]
                     [(live-set) '(rax rbp)]
                     [(graph lives) (Tail tail empty-graph live-set)])
         ;(if (null? graph)
             ;`(locals ,uvar* ,tail)
             `(locals ,uvar* (register-conflict ,graph ,tail)))]
      [,else (invalid who 'Body else)]))

  (define (Block block) ;; Block --> Block
    (match block
      [(,label (lambda () ,[Body -> body])) `(,label (lambda () ,body))]
      [,else (invalid who 'Block else)]))

  (define (Program program) ;; Program --> Program
    (match program
      [(letrec (,[Block -> block*] ...) ,[Body -> body])
       `(letrec ,block* ,body)]
      [,else (invalid who 'Program else)]))

  (Program program))
  
) ;; End Library