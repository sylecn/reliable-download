# reliable-download

Although this project is written in haskell, it is distributed on
[pypi](https://pypi.org/) so that user can install it more easily. Because
python is usually bundled in the system. To install rd-api and rd, see their
[pypi page](https://pypi.org/project/rd-api/). The same doc is in git as well,
see `./pypi/rd-api/README.rst`.

Here is the command help:

```
$ rd-api --help
rd-api - reliable download server

Usage: rd-api [-h|--host HOST] [-p|--port PORT] [--redis-host REDIS_HOST]
              [--redis-port REDIS_PORT] [-d|--web-root DIR] [-w|--worker INT]
              [-v|--verbose] [-V|--version]
  rd-api is an HTTP file server that provides static file hosting and reliable
  download api for rd client.
  
  rd-api serves files under web-root. You can use it like ```python3 -m http.server```
  
  In addition, if rd command line tool is used to do the download, it will
  download in a reliable way by downloading in 2MiB blocks and verify checksum
  for each block.
  
  Usage:
      server side:
          $ ls
          bigfile1 bigfile2
          $ rd-api --host 0.0.0.0 --port 8082
  
      client side:
          $ rd http://server-ip:8082/bigfile1
  
  Reliable download is implemented this way:
  
  - user uses rd client to request a resource to download.
  - rd client requests resource block metadata via the /rd/ api. block metadata
    contains block count, block id, block byte offset, block content sha1sum.
  - rd-api calculates and serves block metadata to rd client incrementally.
    block metadata is cached in redis after calculation.
  - rd client fetches block and verifies sha1sum incrementally. When all blocks
    are downloaded and verified, combine blocks to get the final resource.
  - rd client will retry on http errors and sha1sum verification failures.
  - rd client supports continuing a partial download. You can press Ctrl-C to
    stop download anytime, and continue later by running the same command again.

Available options:
  -h,--host HOST           http listen host (default: "0.0.0.0")
  -p,--port PORT           http listen port (default: 8082)
  --redis-host REDIS_HOST  redis host (default: "127.0.0.1")
  --redis-port REDIS_PORT  redis port (default: 6379)
  -d,--web-root DIR        web root directory (default: ".")
  -w,--worker INT          how many concurrent workers to calculator sha1sum for
                           file (default: 2)
  -v,--verbose             show more debug message
  -V,--version             show program version and exit
  -h,--help                Show this help text

```

```
$ rd --help
rd - reliable download client

Usage: rd [-r|--block-max-retry INT] [-k|--keep] [-d|--temp-dir TEMP_DIR]
          [-o|--output-dir OUTPUT_DIR] [-w|--worker INT] [-f|--force]
          [-v|--verbose] [-V|--version] [URL...]
  Download large files across slow and unstable network reliably. Requires using
  rd-api on server side. For more information, see rd-api --help

Available options:
  -r,--block-max-retry INT max retry times for each block (default: 30)
  -k,--keep                keep block data when download has finished and
                           combined
  -d,--temp-dir TEMP_DIR   the dir to keep block download
                           data (default: ".blocks")
  -o,--output-dir OUTPUT_DIR
                           the dir to keep the final combined
                           file (default: ".")
  -w,--worker INT          concurrent HTTP download worker (default: 5)
  -f,--force               overwrite exiting target file in OUTPUT_DIR
  -v,--verbose             show more debug message
  -V,--version             show version number and exit
  -h,--help                Show this help text
```
