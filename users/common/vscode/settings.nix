let
  fontFamily = "FiraCode Nerd Font";
  fontWeight = "500";
in
{
  "codespaces.accountProvider" = "GitHub";

  "csharp.referencesCodeLens.enabled" = false;

  "debug.javascript.autoAttachFilter" = "disabled";

  "editor.accessibilitySupport" = "off";
  "editor.autoClosingBrackets" = "never";
  "editor.autoClosingQuotes" = "never";
  "editor.autoIndent" = "full";
  "editor.bracketPairColorization.enabled" = true;
  "editor.codeActionsOnSave" = {
    "source.fixAll.eslint" = true;
  };
  "editor.colorDecorators" = true;
  "editor.cursorBlinking" = "solid";
  "editor.cursorStyle" = "line";
  "editor.fontWeight" = fontWeight;
  "editor.fontFamily" = fontFamily;
  "editor.fontLigatures" = true;
  "editor.fontSize" = 16;
  # "editor.lineHeight" = 26;
  "editor.minimap.enabled" = false;
  "editor.multiCursorModifier" = "alt";
  "editor.renderWhitespace" = "none";
  "editor.rulers" = [ 100 ];
  "editor.semanticHighlighting.enabled" = false;
  "editor.suggestSelection" = "first";
  "editor.tabSize" = 2;

  "emmet.syntaxProfiles" = {
    "javascript" = "jsx";
  };
  "emmet.includeLanguages" = {
    "javascript" = "javascriptreact";
  };

  "eslint.packageManager" = "yarn";
  "eslint.validate" = [
    "javascript"
    "javascriptreact"
    "typescript"
    "typescriptreact"
  ];

  "explorer.compactFolders" = false;

  "files.autoSave" = "off";
  "files.associations" = {
    "**/docs/*.md" = "mdx";
    "*.cps" = "javascript";
    ".babelrc" = "jsonc";
    ".eslintignore" = "ignore";
    ".eslintrc" = "jsonc";
    ".prettierrc" = "jsonc";
  };
  "files.encoding" = "utf8";
  "files.eol" = "\n";
  "files.exclude" = {
    "**/.classpath" = true;
    "**/.DS_Store" = true;
    "**/.factorypath" = true;
    "**/.git" = true;
    "**/.hg" = true;
    "**/.project" = true;
    "**/.settings" = true;
    "**/.svn" = true;
    "**/CVS" = true;
  };
  "files.insertFinalNewline" = true;
  "files.trimTrailingWhitespace" = true;

  "git.autofetch" = true;

  "gitlens.gitCommands.skipConfirmations" = [
    "fetch:command"
    "switch:command"
  ];

  "javascript.format.enable" = false;
  "javascript.preferences.importModuleSpecifier" = "relative";
  "javascript.preferences.importModuleSpecifierEnding" = "minimal";
  "javascript.preferences.quoteStyle" = "single";
  "javascript.preferences.useAliasesForRenames" = true;
  "javascript.updateImportsOnFileMove.enabled" = "always";

  "json.format.enable" = false;

  "liveServer.settings.donotVerifyTags" = true;

  "nix.enableLanguageServer" = true;

  "markdown.extension.toc.githubCompatibility" = true;

  "prettier.arrowParens" = "always";
  "prettier.bracketSpacing" = true;
  "prettier.endOfLine" = "lf";
  "prettier.singleQuote" = true;
  "prettier.trailingComma" = "all";
  "prettier.semi" = true;
  "prettier.printWidth" = 80;

  "python.linting.enabled" = true;
  "python.linting.lintOnSave" = true;
  "python.linting.pylintEnabled" = true;

  "search.exclude" = {
    "*.{css,sass,scss}.d.ts" = true;
    ".eslintcache" = true;
    ".git" = true;
    "bower_components" = true;
    "dll" = true;
    "node_modules" = true;
    "npm-debug.log.*" = true;
    "release" = true;
    "test/**/__snapshots__" = true;
    "yarn.lock" = true;
    "**/.yarn" = true;
    "**/.pnp.*" = true;
  };

  "security.workspace.trust.untrustedFiles" = "open";

  "terminal.integrated.cursorBlinking" = false;
  "terminal.integrated.cursorStyle" = "line";
  "terminal.integrated.defaultProfile.linux" = "fish";
  "terminal.integrated.defaultProfile.windows" = "Git Bash";
  "terminal.integrated.drawBoldTextInBrightColors" = false;
  "terminal.integrated.fontFamily" = fontFamily;
  "terminal.integrated.fontWeight" = fontWeight;
  "terminal.integrated.fontSize" = 16;
  "terminal.integrated.cursorWidth" = 2;
  # "terminal.integrated.lineHeight" = 1.2;
  "terminal.integrated.showExitAlert" = false;
  "terminal.integrated.tabs.enabled" = true;

  "typescript.format.enable" = false;
  "typescript.preferences.importModuleSpecifier" = "relative";
  "typescript.preferences.importModuleSpecifierEnding" = "minimal";
  "typescript.preferences.quoteStyle" = "single";
  "typescript.preferences.useAliasesForRenames" = true;
  "typescript.suggest.autoImports" = true;
  "typescript.updateImportsOnFileMove.enabled" = "always";

  "vsicons.associations.files" = [
    {
      "extensionsGlob" = [ "json" ];
      "filename" = true;
      "filenamesGlob" = [ "tsconfig.eslint" ];
      "icon" = "tsconfig";
    }
    {
      "extensionsGlob" = [ "json" ];
      "filename" = true;
      "filenamesGlob" = [ "ormconfig" ];
      "icon" = "db";
    }
    {
      "extensionsGlob" = [ "js" "ts" ];
      "filename" = true;
      "filenamesGlob" = [ "knexfile" ];
      "icon" = "db";
    }
    {
      "extensionsGlob" = [ "js" ];
      "filename" = true;
      "filenamesGlob" = [
        "webpack.config.main.prod"
        "webpack.config.preload"
        "webpack.config.renderer.dev"
        "webpack.config.renderer.dev.dll"
        "webpack.config.renderer.prod"
      ];
      "icon" = "webpack";
    }
  ];
  "vsicons.dontShowNewVersionMessage" = true;
  "vsicons.associations.folders" = [
    {
      "extensions" = [ "infra" ];
      "icon" = "app";
    }
    {
      "extensions" = [ "dll" ];
      "icon" = "binary";
    }
    {
      "extensions" = [ "migrations" "typeorm" ];
      "icon" = "db";
    }
    {
      "extensions" = [ "dtos" "types" ];
      "icon" = "typescript";
    }
    {
      "extensions" = [ "ssr" ];
      "icon" = "client";
    }
    {
      "extensions" = [ "useCases" ];
      "icon" = "services";
    }
    {
      "extensions" = [ "providers" ];
      "icon" = "plugin";
    }
    {
      "extensions" = [ "implementations" "internal" ];
      "icon" = "config";
    }
    {
      "extensions" = [ "fakes" ];
      "icon" = "mock";
    }
    {
      "extensions" = [ "http" ];
      "icon" = "www";
    }
    {
      "extensions" = [ "exceptions" ];
      "icon" = "private";
    }
    {
      "extensions" = [ "logger" ];
      "icon" = "log";
    }
    {
      "extensions" = [ "jobs" ];
      "icon" = "tools";
    }
    {
      "extensions" = [ "store" ];
      "icon" = "redux";
    }
  ];

  "window.zoomLevel" = 0;
  "window.title" = "\${dirty}\${activeEditorShort}\${separator}\${rootName}";

  "workbench.activityBar.visible" = true;
  "workbench.colorTheme" = "doom-one";
  "workbench.editorAssociations" = {
    "*.ipynb" = "jupyter.notebook.ipynb";
  };
  "workbench.iconTheme" = "vscode-icons";
  "workbench.startupEditor" = "none";
  "workbench.view.alwaysShowHeaderActions" = true;

  "[javascript]" = {
    "editor.formatOnSave" = true;
  };

  "[javascriptreact]" = {
    "editor.formatOnSave" = true;
  };

  "[typescript]" = {
    "editor.formatOnSave" = true;
  };

  "[typescriptreact]" = {
    "editor.formatOnSave" = true;
  };

  "[json]" = {
    "editor.formatOnSave" = true;
  };

  "[markdown]" = {
    "editor.formatOnSave" = true;
    "editor.quickSuggestions" = true;
    "editor.wordWrap" = "wordWrapColumn";
    "editor.wordWrapColumn" = 100;
  };

  "[mdx]" = {
    "editor.formatOnSave" = true;
    "editor.quickSuggestions" = true;
    "editor.wordWrap" = "wordWrapColumn";
    "editor.wordWrapColumn" = 100;
  };

  "[python]" = {
    "editor.tabSize" = 4;
    "editor.formatOnSave" = true;
    "editor.wordBasedSuggestions" = false;

    "gitlens.codeLens.symbolScopes" = [ "!Module" ];
  };

  "[plaintext]" = {
    "files.insertFinalNewline" = false;
    "editor.unicodeHighlight.ambiguousCharacters" = false;
  };
}
