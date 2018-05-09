rd-api - reliable download server
========================================

.. version
.. image:: https://img.shields.io/pypi/v/rd-api.svg
    :target: https://pypi.python.org/pypi/rd-api/

.. license
.. image:: https://img.shields.io/pypi/l/rd-api.svg
    :target: https://pypi.python.org/pypi/rd-api/

.. image:: https://img.shields.io/pypi/wheel/rd-api.svg
    :target: https://pypi.python.org/pypi/rd-api/

rd-api is an HTTP file server that provides static file hosting and reliable
download api for `rd client`_.

rd-api serves files under web-root. You can use it like ``python3 -m
http.server``.

In addition, if rd command line tool is used to do the download, it will
download in a reliable way by downloading in 2MiB blocks and verify checksum
for each block.

.. _rd client: https://pypi.org/project/rd/

Installation
------------

To install this package:

.. code-block:: bash

   $ pip install --user rd-api
   $ rd-api --help
   $ ~/.local/bin/rd-api --help     # if ~/.local/bin/ is not in PATH

Baisc Usage
------------

server side:

.. code-block:: sh

   $ ls
   bigfile1 bigfile2
   $ rd-api --host 0.0.0.0 --port 8082

client side (requires `rd client`_):

.. code-block:: sh

   $ rd http://server-ip:8082/bigfile1

Documentation
-------------

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

Reliable download is written in Haskell, binary is distributed on PyPI for
easy installation on linux system. Reliable download only runs in linux.

ChangeLog
---------

* v1.0.0.2 2018-05-09

  - init release.
