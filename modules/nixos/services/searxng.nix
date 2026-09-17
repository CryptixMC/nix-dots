{ ... }:
{
  # Local-only SearXNG instance, backing mcp-searxng (Part II Stage 4's
  # web-search extension for Goose). Deliberately NOT configureUwsgi/nginx —
  # that path is for public or large instances; this is a single-user,
  # localhost-only metasearch backend, so the built-in HTTP server (the
  # option's own default) is the right fit. openFirewall stays unset
  # (false): nothing outside this machine should ever reach it.
  services.searx = {
    enable = true;
    settings = {
      server = {
        port = 8888;
        bind_address = "127.0.0.1";
        # Baked into the world-readable Nix store rather than an
        # environmentFile — acceptable here since this instance only ever
        # binds to 127.0.0.1 with exactly one user (this machine). It only
        # protects CSRF/session state, not query privacy — the privacy
        # property this whole module exists for is that queries never leave
        # the box at all, which self-hosting already guarantees regardless
        # of this key's secrecy.
        secret_key = "b3a1f9e7c4d2a68f0159e7c3a4f2d891b7e6c5a3d9f2018e4c7b9a1f6e3d0852";
        limiter = false;
      };
      search = {
        # json is required — mcp-searxng calls the JSON API, not the HTML UI.
        formats = [
          "html"
          "json"
        ];
      };
    };
  };
}
