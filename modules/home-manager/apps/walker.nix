{ ... }:
{
  xdg.configFile = {

    # ── Main config (float defaults — daemon reads this once at startup) ──────
    "walker/config.toml".text = ''
      theme       = "float"
      placeholder = "search applications…"

      [ui]
        width = 564
    '';

    # ══════════════════════════════════════════════════════════════════════════
    # FLOAT — centered modal, Rofi-style
    # Walker class names from resources/themes/default/style.css:
    #   .box-wrapper  main container
    #   .input        search field
    #   .list         results list
    #   .item-box     row container
    #   .item-subtext secondary label (exec / description)
    #   .normal-icons 16px icon class
    # ══════════════════════════════════════════════════════════════════════════
    "walker/themes/float/style.css".text = ''
      @define-color window_bg_color #0a0a0d;
      @define-color accent_bg_color #b047ff;
      @define-color theme_fg_color  #f5f5f5;

      * { all: unset; font-family: "JetBrainsMono Nerd Font Mono", monospace; }

      scrollbar { opacity: 0; }

      .box-wrapper {
        background:    rgba(10,10,13,0.97);
        border-radius: 8px;
        border:        1px solid #1c1c1c;
        box-shadow:    0 16px 56px rgba(0,0,0,.95), 0 0 0 1px rgba(176,71,255,0.07);
        min-width:     564px;
      }

      .search-container {
        padding:       10px 15px 8px;
        border-bottom: 1px solid #0d0d0d;
      }

      .input {
        background:    #0c0c0f;
        color:         #f5f5f5;
        border:        1px solid #9150ff;
        border-radius: 4px;
        box-shadow:    0 0 0 2px rgba(145,80,255,0.15);
        font-size:     13px;
        padding:       9px 11px;
        caret-color:   #b047ff;
      }

      .input placeholder { color: #2e2e2e; opacity: 1; }

      .list { padding: 4px 7px; color: #c8c8c8; }

      .item-box {
        border-radius: 4px;
        padding:       7px 9px 7px 11px;
        margin:        1px 0;
        border-left:   2px solid transparent;
      }

      child:selected .item-box,
      row:selected   .item-box {
        background:  rgba(176,71,255,0.12);
        border-left: 2px solid #b047ff;
      }

      .item-subtext { font-size: 10px; color: #373737; opacity: 1; }

      child:selected .item-subtext,
      row:selected   .item-subtext { color: #9f4eff; }

      .normal-icons { -gtk-icon-size: 15px; color: #373737; }

      child:selected .normal-icons,
      row:selected   .normal-icons { color: #b047ff; }
    '';

    # ══════════════════════════════════════════════════════════════════════════
    # RAIL — compact sidebar panel
    # ══════════════════════════════════════════════════════════════════════════
    "walker/themes/rail/style.css".text = ''
      @define-color window_bg_color #08080b;
      @define-color accent_bg_color #b047ff;
      @define-color theme_fg_color  #f5f5f5;

      * { all: unset; font-family: "JetBrainsMono Nerd Font Mono", monospace; }

      scrollbar { opacity: 0; }

      .box-wrapper {
        background:   rgba(8,8,11,0.99);
        border-right: 1px solid #0d0d0d;
        border-radius: 0;
        min-width:    272px;
        max-width:    272px;
      }

      .search-container {
        padding:       10px 12px 8px;
        border-bottom: 1px solid #0d0d0d;
      }

      .input {
        background:    #0c0c0f;
        color:         #f5f5f5;
        border:        1px solid #9150ff;
        border-radius: 4px;
        box-shadow:    0 0 0 2px rgba(145,80,255,0.12);
        font-size:     12px;
        padding:       7px 9px;
        caret-color:   #b047ff;
      }

      .input placeholder { color: #2e2e2e; opacity: 1; }

      .list { padding: 2px 8px; color: #c8c8c8; }

      .item-box {
        border-radius: 3px;
        padding:       5px 7px 5px 10px;
        margin:        1px 0;
        border-left:   2px solid transparent;
      }

      child:selected .item-box,
      row:selected   .item-box {
        background:  rgba(176,71,255,0.12);
        border-left: 2px solid #b047ff;
      }

      .item-subtext { font-size: 10px; color: #373737; opacity: 1; }

      child:selected .item-subtext,
      row:selected   .item-subtext { color: #9f4eff; }

      .normal-icons { -gtk-icon-size: 13px; color: #373737; }

      child:selected .normal-icons,
      row:selected   .normal-icons { color: #b047ff; }
    '';

    # ══════════════════════════════════════════════════════════════════════════
    # GRID — full-screen overlay, large icon tiles
    # ══════════════════════════════════════════════════════════════════════════
    "walker/themes/grid/style.css".text = ''
      @define-color window_bg_color #050508;
      @define-color accent_bg_color #b047ff;
      @define-color theme_fg_color  #f5f5f5;

      * { all: unset; font-family: "JetBrainsMono Nerd Font Mono", monospace; }

      scrollbar { opacity: 0; }

      .box-wrapper {
        background:    rgba(5,5,8,0.92);
        border-radius: 0;
      }

      .search-container { padding: 12px 80px 14px; }

      .input {
        background:    rgba(12,12,16,0.96);
        color:         #f5f5f5;
        border:        1px solid #9f4eff;
        border-radius: 6px;
        box-shadow:    0 0 0 3px rgba(159,78,255,0.12), 0 8px 28px rgba(0,0,0,.65);
        font-size:     14px;
        padding:       12px 14px;
        caret-color:   #b047ff;
      }

      .input placeholder { color: #2e2e2e; opacity: 1; }

      .list { padding: 8px 48px; color: #c8c8c8; }

      .item-box {
        background:    rgba(12,12,16,0.55);
        border:        1px solid rgba(28,28,28,0.9);
        border-radius: 6px;
        padding:       17px 8px 12px;
        margin:        4px;
        min-width:     120px;
      }

      child:selected .item-box,
      row:selected   .item-box {
        background: rgba(176,71,255,0.13);
        border:     1px solid rgba(176,71,255,0.4);
      }

      .item-subtext {
        font-size:      8px;
        color:          #373737;
        opacity:        1;
        letter-spacing: 0.07em;
        text-transform: uppercase;
      }

      child:selected .item-subtext,
      row:selected   .item-subtext { color: #9f4eff; }

      .large-icons { -gtk-icon-size: 30px; color: #373737; }

      child:selected .large-icons,
      row:selected   .large-icons { color: #b047ff; }
    '';
  };
}
