#!/bin/sh

render_readme() {
    python3 -m readme_renderer -o "$2" "$1"
}

exit_code=0

render_readme "pypi/rd-api/README.rst" "build/rd-api.html" || exit_code=1
render_readme "pypi/rd-client/README.rst" "build/rd.html" || exit_code=1

exit $exit_code
