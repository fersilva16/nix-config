(defvar bootstrap-version)
(let ((bootstrap-file
       (expand-file-name "straight/repos/straight.el/bootstrap.el" user-emacs-directory))
      (bootstrap-version 5))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
	(url-retrieve-synchronously
	 "https://raw.githubusercontent.com/raxod502/straight.el/develop/install.el"
	 'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

(straight-use-package 'use-package)
(setq straight-use-package-by-default t)

(defun display-startup-time ()
  "A simple function that display in how much seconds this config has been loaded."
  (message "Emacs loaded in %s with %d garbage collections."
           (format "%.2f seconds"
                   (float-time
                    (time-subtract after-init-time before-init-time)))
           gcs-done))

(add-hook 'emacs-startup-hook #'display-startup-time)

(setq inhibit-startup-message t)

(scroll-bar-mode -1)
(tool-bar-mode -1)
(tooltip-mode -1)
(menu-bar-mode -1)
(set-fringe-mode 10)
(line-number-mode)

(setq visible-bell nil)

(set-face-attribute 'default nil :font "FiraCode Nerd Font")

(use-package general)

(use-package projectile
  :init (projectile-mode t))

(use-package which-key
  :init (which-key-mode))

(use-package evil
  :ensure t
  :init
  (setq evil-want-integration t)
  (setq evil-want-keybinding nil)
  :config
  (evil-mode 1))

(use-package evil-collection
  :after evil
  :ensure t
  :config
  (evil-collection-init))

(use-package ivy
  :bind (("C-s" . swiper)
	 :map ivy-minibuffer-map
	 ("TAB" . ivy-alt-done)
	 ("C-l" . ivy-alt-done)
	 ("C-j" . ivy-next-line)
	 ("C-k" . ivy-previous-line)
	 :map ivy-switch-buffer-map
	 ("C-k" . ivy-previous-line)
	 ("C-l" . ivy-done)
	 ("C-d" . ivy-switch-buffer-kill)
	 :map ivy-reverse-i-search-map
	 ("C-k" . ivy-previous-line)
	 ("C-d" . ivy-reverse-i-search-kill))
  :config (ivy-mode 1))

(use-package vertico
  :init
  (vertico-mode))

(use-package company
  :init
  (add-hook 'after-init-hook 'global-company-mode))

(use-package savehist
  :init
  (savehist-mode))

(use-package undo-tree
  :init (global-undo-tree-mode)
  :config
  (setq undo-tree-history-directory-alist '(("." . "~/.emacs.d/undo"))
        undo-tree-visualizer-diff t
        undo-tree-auto-save-history t
        undo-tree-enable-undo-in-region t
        undo-limit 800000
        undo-strong-limit 12000000
        undo-outer-limit 128000000))

(use-package emacs
  :init
  (defun crm-indicator (args)
    (cons (format "[CRM%s] %s"
                  (replace-regexp-in-string
                   "\\`\\[.*?]\\*\\|\\[.*?]\\*\\'" ""
                   crm-separator)
                  (car args))
          (cdr args)))
  (advice-add #'completing-read-multiple :filter-args #'crm-indicator)

  (setq minibuffer-prompt-properties
        '(read-only t cursor-intangible t face minibuffer-prompt))
  (add-hook 'minibuffer-setup-hook #'cursor-intangible-mode)

  (setq enable-recursive-minibuffers t))

(use-package doom-themes
  :config
  (setq doom-themes-enable-bold t
        doom-themes-enable-italic t)
  (load-theme 'doom-one t)
  (doom-themes-visual-bell-config)
  (doom-themes-org-config))

(use-package emacsql)
(use-package emacsql-sqlite)

(defmacro letf! (bindings &rest body)
  "Temporarily rebind function, macros, and advice in BODY.
Intended as syntax sugar for `cl-letf', `cl-labels', `cl-macrolet', and
temporary advice.
BINDINGS is either:
  A list of, or a single, `defun', `defun*', `defmacro', or `defadvice' forms.
  A list of (PLACE VALUE) bindings as `cl-letf*' would accept.
TYPE is one of:
  `defun' (uses `cl-letf')
  `defun*' (uses `cl-labels'; allows recursive references),
  `defmacro' (uses `cl-macrolet')
  `defadvice' (uses `defadvice!' before BODY, then `undefadvice!' after)
NAME, ARGLIST, and BODY are the same as `defun', `defun*', `defmacro', and
`defadvice!', respectively.
\(fn ((TYPE NAME ARGLIST &rest BODY) ...) BODY...)"
  (declare (indent defun))
  (setq body (macroexp-progn body))
  (when (memq (car bindings) '(defun defun* defmacro defadvice))
    (setq bindings (list bindings)))
  (dolist (binding (reverse bindings) body)
    (let ((type (car binding))
          (rest (cdr binding)))
      (setq
       body (pcase type
              (`defmacro `(cl-macrolet ((,@rest)) ,body))
              (`defadvice `(progn (defadvice! ,@rest)
                                  (unwind-protect ,body (undefadvice! ,@rest))))
              ((or `defun `defun*)
               `(cl-letf ((,(car rest) (symbol-function #',(car rest))))
                  (ignore ,(car rest))
                  ,(if (eq type 'defun*)
                       `(cl-labels ((,@rest)) ,body)
                     `(cl-letf (((symbol-function #',(car rest))
                                 (lambda! ,(cadr rest) ,@(cddr rest))))
                        ,body))))
              (_
               (when (eq (car-safe type) 'function)
                 (setq type (list 'symbol-function type)))
               (list 'cl-letf (list (cons type rest)) body)))))))


(use-package org-roam
  :hook (org-load . +org-init-roam-h)
  :config
  (setq org-directory "~/org"
    org-roam-directory (concat org-directory "/roam")
    org-roam-dailies-directory (concat org-roam-directory "/dailies")
    org-agenda-files `(,(concat org-directory "/inbox.org")))

  (defun +org-init-roam-h ()
  (letf! ((#'org-roam-db-sync #'ignore))
    (org-roam-db-autosync-enable)))

  (setq org-roam-capture-templates '(("n" "note" plain "%?"
    :if-new (file+head "${slug}.org"
                       "#+title: ${title}\n#+date: %<%Y-%m-%d %H:%M:%S>\n\n* ${title}")
    :unnarrowed t)))

  (setq org-roam-dailies-capture-templates '(("d" "daily" plain "%?"
    :if-new (file+head "%<%Y-%m-%d>.org"
                        "#+title: %<%Y-%m-%d>\n\n* %<%Y-%m-%d>")
    :unnarrowed t))))

(setq org-todo-keywords
  '((sequence "TODO(t)" "|" "DONE(d)")
    (sequence "HOLD(h)" "PROJ(p)" "|" "CANC(k)")
    (sequence "HABIT(a)" "|" "CHECK(c)")))

(add-hook 'org-mode-hook #'org-indent-mode)

(use-package org-superstar
  :init (add-hook 'org-mode-hook (lambda () (org-superstar-mode 1))))

(setq org-hide-leading-stars t
      org-indent-mode-turns-on-hiding-stars nil)

(use-package websocket
  :after org-roam)

(use-package org-roam-ui
  :after org-roam
  :config
  (setq org-roam-ui-sync-theme t
  org-roam-ui-follow t
  org-roam-ui-update-on-save t
  org-roam-ui-open-on-start nil))

(add-hook 'org-mode-hook (lambda () (setq truncate-lines nil)))

(add-to-list 'org-modules 'org-habit)

(use-package org-drill
  :config
  (require 'org-drill))

(use-package org-cliplink)

(use-package wakatime-mode
  :config
  (global-wakatime-mode)
  (setq wakatime-api-key "460ec448-4d21-4765-8457-4444866f5f46"
        wakatime-cli-path "wakatime-cli"))

(use-package git-gutter)
(global-git-gutter-mode +1)

(use-package git-gutter-fringe)

(define-fringe-bitmap 'git-gutter-fr:added [224] nil nil '(center repeated))
(set-face-foreground 'git-gutter-fr:added "#98be65")

(define-fringe-bitmap 'git-gutter-fr:modified [224] nil nil '(center repeated))
(set-face-foreground 'git-gutter-fr:modified "#da8548")

(define-fringe-bitmap 'git-gutter-fr:deleted [128 192 224 240] nil nil 'bottom)
(set-face-foreground 'git-gutter-fr:deleted "#ff6c6b")

(use-package ledger-mode)

(defun notes-push ()
  (interactive)
  (shell-command "notes-push"))

(run-with-timer (* 30 60) (* 30 60) 'notes-push)

(defun my-project-root (&optional dir)
  (let ((projectile-project-root
         (unless dir (bound-and-true-p projectile-project-root)))
        projectile-require-project-root)
    (projectile-project-root dir)))

(defun my-project-find-file (dir)
  (unless (file-directory-p dir)
    (error "Directory %S does not exist" dir))
  (unless (file-readable-p dir)
    (error "Directory %S isn't readable" dir))
  (let* ((default-directory (file-truename dir))
         (projectile-project-root (my-project-root dir)))
    (call-interactively #'projectile-find-file)))

(defun find-in-notes ()
  (interactive)
  (my-project-find-file org-directory))

(defun open-inbox ()
  (interactive)
  (find-file "~/org/inbox.org"))

(general-create-definer leader-def
  :prefix "SPC")

(general-create-definer localleader-def
  :prefix "SPC m")

(leader-def
 :states 'normal
 :keymaps 'override
 ":" #'execute-extended-command
 "b" '(:ignore t :wk "buffers")
 "b b" #'switch-to-buffer
 "b k" #'kill-current-buffer
 "f" '(:ignore t :wk "files")
 "f o" #'find-file
 "f s" #'save-buffer
 "h" '(:keymap help-map :wk "help")
 "m" '(:ignore t :wk "<localleader>")
 "n" '(:ignore t :wk "notes")
 "n a" #'org-agenda
 "n d" '(:ignore t :wk "dailies")
 "n d D" #'org-roam-dailies-capture-date
 "n d d" #'org-roam-dailies-goto-date
 "n d M" #'org-roam-dailies-capture-tomorrow
 "n d m" #'org-roam-dailies-goto-tomorrow
 "n d T" #'org-roam-dailies-capture-today
 "n d t" #'org-roam-dailies-goto-today
 "n d Y" #'org-roam-dailies-capture-yesterday
 "n d y" #'org-roam-dailies-goto-yesterday
 "n f" #'find-in-notes
 "n i" #'open-inbox
 "n p" #'notes-push
 "n r" '(:ignore t :wk "roam")
 "n r f" #'org-roam-node-find
 "n r i" #'org-roam-node-insert
 "n r n" #'org-roam-capture
 "n s" #'org-save-all-org-buffers
 "w" '(:keymap evil-window-map :wk "windows"))

(localleader-def
  :states 'normal
  :keymaps 'emacs-lisp-mode-map
  "e" #'eval-buffer)

(localleader-def
  :states 'normal
  :keymaps 'org-mode-map
  "l" '(:ignore t :wk "links")
  "l c" #'org-cliplink
  "l l" #'org-insert-link)
