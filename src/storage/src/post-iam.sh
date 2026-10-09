#!/usr/bin/env bash
########################################################################################################################
# IAM credentials
########################################################################################################################
echo -n "$ACCESS" | pass insert --force --multiline "${PREFIX}.access" >/dev/null &&
    echo -n "$SECRET" | pass insert --force --multiline "${PREFIX}.secret" >/dev/null
