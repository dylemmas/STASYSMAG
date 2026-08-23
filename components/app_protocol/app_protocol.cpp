#include "app_protocol.h"

#include <string.h>

#include "mbedtls/sha256.h"

static void put_u16_le(uint8_t *out, uint16_t value)
{
    out[0] = (uint8_t)(value & 0xffu);
    out[1] = (uint8_t)(value >> 8);
}

static void put_i16_le(uint8_t *out, int16_t value)
{
    put_u16_le(out, (uint16_t)value);
}

static void put_f32_le(uint8_t *out, float value)
{
    uint32_t bits;
    memcpy(&bits, &value, sizeof(bits));
    out[0] = (uint8_t)(bits & 0xffu);
    out[1] = (uint8_t)((bits >> 8) & 0xffu);
    out[2] = (uint8_t)((bits >> 16) & 0xffu);
    out[3] = (uint8_t)(bits >> 24);
}

size_t staysys_packet_serialize(const staysys_packet_payload_t *payload,
                                uint8_t output[STASYS_PACKET_SIZE])
{
    if (payload == NULL || output == NULL) {
        return 0;
    }

    output[0] = STASYS_PACKET_HEADER_0;
    output[1] = STASYS_PACKET_HEADER_1;
    put_f32_le(&output[2], payload->ax);
    put_f32_le(&output[6], payload->ay);
    put_f32_le(&output[10], payload->az);
    put_f32_le(&output[14], payload->gx);
    put_f32_le(&output[18], payload->gy);
    put_f32_le(&output[22], payload->gz);
    put_i16_le(&output[26], payload->mag_x);
    put_i16_le(&output[28], payload->mag_y);
    put_i16_le(&output[30], payload->mag_z);
    put_u16_le(&output[32], payload->piezo);
    output[34] = payload->battery;

    output[35] = 0;
    for (size_t i = 2; i < 35; ++i) {
        output[35] ^= output[i];
    }
    return STASYS_PACKET_SIZE;
}

int staysys_auth_digest(const char *challenge, size_t challenge_len,
                        char output_hex[65])
{
    if (challenge == NULL || output_hex == NULL || challenge_len == 0 ||
        challenge_len > STASYS_MAX_CHALLENGE_LEN) {
        return -1;
    }

    mbedtls_sha256_context context;
    unsigned char digest[32];
    mbedtls_sha256_init(&context);
    mbedtls_sha256_starts(&context, 0);
    mbedtls_sha256_update(&context,
                          (const unsigned char *)challenge,
                          challenge_len);
    mbedtls_sha256_update(&context,
                          (const unsigned char *)STASYS_SECRET_KEY,
                          strlen(STASYS_SECRET_KEY));
    mbedtls_sha256_finish(&context, digest);
    mbedtls_sha256_free(&context);
    mbedtls_sha256_free(&context);

    static const char hex[] = "0123456789abcdef";
    for (size_t i = 0; i < sizeof(digest); ++i) {
        output_hex[i * 2] = hex[digest[i] >> 4];
        output_hex[i * 2 + 1] = hex[digest[i] & 0x0f];
    }
    output_hex[64] = '\0';
    return 0;
}
