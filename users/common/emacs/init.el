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

(use-package which-key
  :init (which-key-mode))

(general-define-key
 :states 'normal
 :prefix "SPC"
 ":" 'execute-extended-command
 "f o" 'find-file
 "f e" 'eval-buffer
 "f s" 'save-buffer
 "b k" 'kill-current-buffer
 "w k" 'evil-quit
 "h" help-map)

(use-package evil
  :config (evil-mode 1))

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

(use-package nano-theme
  :straight (:type git :host github
		   :repo "rougier/nano-theme")
  :config (nano-dark))

(use-package emacsql)
(use-package emacsql-sqlite)

(use-package org-roam
  :after '(emacsql emacsql-sqlite))
  :config
  (setq org-roam-capture-templates '(("n" "note" plain "%?"
    :if-new (file+head "${slug}.org"
                       "#+title: ${title}\n#+date: %<%Y-%m-%d %H:%M:%S>\n\nTags: \n\n* ${title}")
    :unnarrowed t)))

(setq org-directory "~/org"
	org-roam-directory (concat org-directory "/roam")
	org-roam-dailies-directory (concat org-roam-directory "/dailies")
	org-agenda-files '(concat ))

(use-package org-modern
  :init
  (add-hook 'org-mode-hook #'org-modern-mode)
  (add-hook 'org-agenda-finalize-hook #'org-modern-agenda))

(use-package websocket
  :after org-roam)

(use-package org-roam-ui
  :after org-roam
  :config
  (setq org-roam-ui-sync-theme t
  org-roam-ui-follow t
  org-roam-ui-update-on-save t
  org-roam-ui-open-on-start nil))
