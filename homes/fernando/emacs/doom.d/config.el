(setq doom-font (font-spec :family "CaskaydiaCove Nerd Font"))

(setq doom-unicode-font doom-font)

(setq user-full-name "Fernando Silva"
      user-full-name "fernandonsilva16@gmail.com")

(setq confirm-kill-emacs nil)

(setq company-idle-delay nil)

(global-wakatime-mode)

(setq org-directory "~/org"
      org-roam-directory (concat org-directory "/roam")
      org-roam-dailies-directory (concat org-roam-directory "/dailies")
      org-agenda-files '(concat ))

(after! org-roam
  (setq org-roam-capture-templates
        '(("n" "note" plain "%?"
           :if-new (file+head "${slug}.org"
                              "#+title: ${title}\n#+date: %<%Y-%m-%d %H:%M:%S>\n\nTags: \n\n* ${title}")
           :unnarrowed t))))

(use-package! websocket
  :after org-roam)

(use-package! org-roam-ui
  :after org-roam
  :config
  (setq org-roam-ui-sync-theme t
        org-roam-ui-follow t
        org-roam-ui-update-on-save t
        org-roam-ui-open-on-start nil))

(add-hook 'org-mode-hook #'org-modern-mode)
(add-hook 'org-agenda-finalize-hook #'org-modern-agenda)

(when (and (featurep! :completion company) (featurep! :lang nix))
  (after! company
    (setq-hook! 'nix-mode-hook company-idle-delay nil)))

(use-package! nix-mode
  :interpreter ("\\(?:cached-\\)?nix-shell" . +nix-shell-init-mode)
  :mode "\\.nix\\'"
  :init
  (add-to-list 'auto-mode-alist
               (cons "/flake\\.lock\\'"
                     (if (featurep! :lang json)
                         'json-mode
                       'js-mode)))
  :config
  (after! lsp-mode
    (add-to-list 'lsp-language-id-configuration '(nix-mode . "nix"))

    (lsp-register-client
     (make-lsp-client :new-connection (lsp-stdio-connection '("rnix-lsp"))
                      :major-modes '(nix-mode)
                      :server-id 'nix))

    )
  (add-hook 'nix-mode-hook #'lsp!)

  (set-popup-rule! "^\\*nixos-options-doc\\*$" :ttl 0 :quit t)

  (setq-hook! 'nix-mode-hook company-idle-delay nil)

  (map! :localleader
        :map nix-mode-map
        "f" #'nix-update-fetch
        "p" #'nix-format-buffer
        "r" #'nix-repl-show
        "s" #'nix-shell
        "b" #'nix-build
        "u" #'nix-unpack
        "o" #'+nix/lookup-option))

(use-package! nix-drv-mode
  :mode "\\.drv\\'")

(setq lsp-haskell-plugin-ghcide-type-lenses-global-on nil)
(setq lsp-haskell-plugin-import-lens-code-lens-on nil)
