(setq doom-font (font-spec :family "Caskaydia Cove Nerd Font"))

(after! lsp
(add-to-list 'lsp-language-id-configuration '(nix-mode . "nix"))
(lsp-register-client
  (make-lsp-client :new-connection (lsp-stdio-connection '("rnix-lsp"))
                   :major-modes '(nix-mode)
                   :server-id 'nix)))
