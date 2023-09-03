# waap-nginx

WAAP(Web app and API protection) solutions protect against application security risks from vulnerability exploits, bots,
automated attacks, denial of service, fraud and abuse, and insecure third-party API integrations.

# Status

in development

# Build

```shell
git clone --recurse-submodules --depth=2 https://github.com/NilShieldLabs/waap-nginx.git

cd waap-nginx

docker build --force-rm -t waap-nginx:latest .

mkdir build || true

docker cp waap-nginx:/opt/waap build/waap

```

# License

* [waap-nginx](LICENSE): Apache 2.0, see [LICENSE](LICENSE)
* [Dependencies](LICENSES.txt): see [LICENSES.txt](LICENSES.txt)

# Thanks

This project relies on a large number of open source project results, thanks to all developers
