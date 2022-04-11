(setq doom-font (font-spec :family "Caskaydia Cove Nerd Font"))

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
