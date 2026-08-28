#pragma once

#include <stdint.h>
#include <stddef.h>

#define STASYS_PACKET_SIZE 36u
#define STASYS_PACKET_PAYLOAD_SIZE 33u
#define STASYS_PACKET_HEADER_0 0xAAu
#define STASYS_PACKET_HEADER_1 0xBBu
#define STASYS_MAX_CHALLENGE_LEN 128u
#define STASYS_SECRET_KEY "12ebaf10h12fa9123z21sti"

typedef struct {
    float ax;
    float ay;
    float az;
    float gx;
    float gy;
    float gz;
    int16_t mag_x;
    int16_t mag_y;
    int16_t mag_z;
    uint16_t piezo;
    uint8_t battery;
} staysys_packet_payload_t;

#ifdef __cplusplus
static_assert(sizeof(float) == 4, "STASYS requires IEEE-754 float32");
#endif

#ifdef __cplusplus
extern "C" {
#endif

size_t staysys_packet_serialize(const staysys_packet_payload_t *payload,
                                uint8_t output[STASYS_PACKET_SIZE]);
int staysys_auth_digest(const char *challenge, size_t challenge_len,
                        char output_hex[65]);

#ifdef __cplusplus
}
#endif
