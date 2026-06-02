rd - reliable download command line tool
========================================

.. image:: https://img.shields.io/pypi/v/rd.svg
    :target: https://pypi.org/project/rd/

.. image:: https://img.shields.io/pypi/l/rd.svg
    :target: https://pypi.org/project/rd/

.. image:: https://img.shields.io/pypi/wheel/rd.svg
    :target: https://pypi.org/project/rd/

Download large files across slow and unstable network reliably. Requires using
rd-api on server side. For more information on how it works, see rd-api_.

Installation
------------

To install this package:

For Debian/Ubuntu,

.. code-block:: bash

   $ sudo apt install -y pipx
   $ pipx install rd

For RHEL,

.. code-block:: bash

   $ sudo dnf install python3-pip
   $ pip install --user rd

To run rd

.. code-block:: bash

   $ rd --help
   $ ~/.local/bin/rd --help     # if ~/.local/bin/ is not in PATH

Baisc Usage
------------

server side (requires rd-api_):

.. code-block:: bash

   $ ls
   bigfile1 bigfile2
   $ rd-api --host 0.0.0.0 --port 8082

client side:

.. code-block:: bash

   $ rd http://server-ip:8082/bigfile1

Documentation
-------------

see rd-api_.

.. _rd-api: https://pypi.org/project/rd-api/

License
---------------

Reliable download is released under GPLv3+. Source code can be found at
https://gitlab.emacsos.com/sylecn/reliable-download

ChangeLog
---------

* v1.7.0.0 2026-06-02

  - bugfix: fix log message timestamp is static issue.

* v1.6.0.0 2024-04-26

  - bugfix: don't print no block fetched in last N seconds when all blocks are fetched.

* v1.5.0.0 2024-04-08

  - bugfix: properly handle unicode string in URL path
  - bugfix: use local time in log messages instead of UTC time
  - bugfix: rd client now supports ipv6 address in URL

* v1.3.0.0 2022-03-15

  - feature: add download progress logging

* v1.2.0.0 2022-03-14

  - feature: add ``--rolling-combine`` option. allow combine big file when disk space is low.

* v1.1.3.0 2022-03-14

  - feature: code ported to ghc 8.10.7

* v1.0.0.3 2018-05-09

  - init release.
