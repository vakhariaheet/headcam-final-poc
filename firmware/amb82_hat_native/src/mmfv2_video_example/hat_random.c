#include "osdep_service.h"

#include "hat_crypto.h"

bool hat_random_bytes(uint8_t *out, size_t len)
{
	return rtw_get_random_bytes(out, len) == 0;
}
