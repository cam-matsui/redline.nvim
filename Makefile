.PHONY: test lint format

test:
	nvim -l tests/run.lua

lint:
	stylua --check lua/ plugin/ tests/

format:
	stylua lua/ plugin/ tests/
