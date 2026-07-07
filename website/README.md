# Elui Website

Static marketing/documentation site for `https://elui.sh`.

Open locally:

```sh
open website/index.html
```

The GitHub Pages workflow deploys this directory and includes `CNAME` for the
custom domain.

## DNS

GitHub Pages is configured with the custom domain `elui.sh`. Namecheap still
needs DNS records before the domain resolves:

| Type | Host | Value |
| --- | --- | --- |
| `A` | `@` | `185.199.108.153` |
| `A` | `@` | `185.199.109.153` |
| `A` | `@` | `185.199.110.153` |
| `A` | `@` | `185.199.111.153` |
| `CNAME` | `www` | `douglascorrea.github.io` |

After DNS propagates, GitHub can enforce HTTPS for `https://elui.sh`.
