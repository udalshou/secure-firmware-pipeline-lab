#!/usr/bin/env bash
# Negative test for CI: unquoted expansion (SC2086) must fail the os job.
echo $1
