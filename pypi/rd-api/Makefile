VERSION := $(shell grep 'version:' ../../package.yaml | cut -d':' -f2 | tr -d ' ')

default:
	@echo "usage: make [dist|install|upload]"
bootstrap:
	@if ! python3 -c 'import readme_renderer'; then python3 -m pip install --user readme_renderer ; fi
	@test -f ~/.local/bin/wheel || python3 -m pip install --user wheel
	@test -f ~/.local/bin/twine || python3 -m pip install --user twine
check: bootstrap
	python3 setup.py check -r -s
dist: check
	cp -u `stack path --local-install-root`/bin/rd-api rdapi/
	rm -rf dist/*
	python3 setup.py -q bdist_wheel --universal
upload: dist
	~/.local/bin/twine upload dist/*
testupload: dist
	env TWINE_PASSWORD=XVgnIVGGFjlMRxDV ~/.local/bin/twine upload --repository-url https://test.pypi.org/legacy/ dist/*
install: dist
	python3 -m pip install --user dist/rd_api-$(VERSION)-py2.py3-none-any.whl
.PHONY: default twine dist upload install
