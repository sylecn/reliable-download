module RD.Server.Cli.OptsDoc where

rdApiDescription :: String
rdApiDescription = "rd-api is an HTTP file server that provides static file hosting and reliable\n\
\download api for rd client.\n\
\\n\
\rd-api serves files under web-root. You can use it like python3 -m http.server\n\
\\n\
\In addition, if rd command line tool is used to do the download, it will\n\
\download in a reliable way by downloading in 2MiB blocks and verify checksum\n\
\for each block.\n\
\\n\
\Usage:\n\
\    server side:\n\
\        $ ls\n\
\        bigfile1 bigfile2\n\
\        $ rd-api --host 0.0.0.0 --port 8082\n\
\\n\
\    client side:\n\
\        $ rd http://server-ip:8082/bigfile1\n\
\\n\
\Reliable download is implemented this way:\n\
\\n\
\- user uses rd client to request a resource to download.\n\
\- rd client requests resource block metadata via the /rd/ api. block metadata\n\
\  contains block count, block id, block byte offset, block content sha1sum.\n\
\- rd-api calculates and serves block metadata to rd client incrementally.\n\
\  block metadata is cached in redis after calculation.\n\
\- rd client fetches block and verifies sha1sum incrementally. When all blocks\n\
\  are downloaded and verified, combine blocks to get the final resource.\n\
\- rd client will retry on http errors and sha1sum verification failures.\n\
\- rd client supports continuing a partial download. You can press Ctrl-C to\n\
\  stop download anytime, and continue later by running the same command again."
