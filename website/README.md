# Elui Website

Static marketing/documentation site for `https://elui.sh`.

Open locally:

```sh
open website/index.html
```

The GitHub Pages workflow deploys this directory and includes `CNAME` for the
custom domain.

## DNS

GitHub Pages is configured with the custom domain `elui.sh`. Namecheap is
configured with:

| Type | Host | Value |
| --- | --- | --- |
| `ALIAS` | `@` | `douglascorrea.github.io` |
| `CNAME` | `www` | `douglascorrea.github.io` |

GitHub Pages also supports apex `A` records, but this domain uses Namecheap's
`ALIAS` record for the apex because it tracks the GitHub Pages target directly.
After DNS propagates, GitHub can enforce HTTPS for `https://elui.sh`.
