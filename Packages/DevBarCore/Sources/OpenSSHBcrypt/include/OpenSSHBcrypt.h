#ifndef OPENSSH_BCRYPT_H
#define OPENSSH_BCRYPT_H

#include <stddef.h>
#include <stdint.h>

#include "blf.h"

int devbar_bcrypt_pbkdf(
    const char *pass,
    size_t passlen,
    const uint8_t *salt,
    size_t saltlen,
    uint8_t *key,
    size_t keylen,
    unsigned int rounds
);

#endif /* OPENSSH_BCRYPT_H */
