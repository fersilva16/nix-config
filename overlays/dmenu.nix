self: super:
super.dmenu.overrideAttrs (oldAttrs: {
  patches = (if oldAttrs.patches == null then [ ] else oldAttrs.patches) ++ [
    (self.fetchpatch {
      url = "https://tools.suckless.org/dmenu/patches/case-insensitive/dmenu-caseinsensitive-5.0.diff";
      sha256 = "sha256-XqFEBRu+aHaAXrNn+WXnkIuC/vAHDIb/im2UhjaPYC0=";
    })
    (self.fetchpatch {
      url = "https://tools.suckless.org/dmenu/patches/line-height/dmenu-lineheight-5.0.diff";
      sha256 = "sha256-St1x4oZCqDnz7yxw7cQ0eUDY2GtL+4aqfUy8Oq5fWJk=";
    })
  ];
})
