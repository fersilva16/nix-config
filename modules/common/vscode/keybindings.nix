[
  {
    key = "ctrl+'";
    command = "workbench.action.terminal.toggleTerminal";
  }
  {
    key = "ctrl+shift+[BracketLeft]";
    command = "-workbench.action.terminal.toggleTerminal";
  }
  {
    key = "shift+alt+up";
    command = "-editor.action.insertCursorAbove";
    when = "editorTextFocus";
  }
  {
    key = "shift+alt+down";
    command = "-editor.action.insertCursorBelow";
    when = "editorTextFocus";
  }
  {
    key = "shift+alt+down";
    command = "editor.action.copyLinesDownAction";
    when = "editorTextFocus && !editorReadonly";
  }
  {
    key = "ctrl+shift+alt+down";
    command = "-editor.action.copyLinesDownAction";
    when = "editorTextFocus && !editorReadonly";
  }
  {
    key = "shift+alt+up";
    command = "editor.action.copyLinesUpAction";
    when = "editorTextFocus && !editorReadonly";
  }
  {
    key = "ctrl+shift+alt+up";
    command = "-editor.action.copyLinesUpAction";
    when = "editorTextFocus && !editorReadonly";
  }
]
