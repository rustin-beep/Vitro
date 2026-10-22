#include <stdio.h>
#include <string.h>
#include "wav.h"

int main(void)
{
    WavData wav;
    WavData parsed;
    WavStats before;
    WavStats after;
    unsigned char buffer[512];
    int length;
    int rc;
    int clipped = 0;
    int start = 0;
    int silence = 0;
    int same = 1;
    int i;

    wav_init(&wav, 8000, 1, 8);
    wav.sample_count = 1600;
    wav_generate_test_signal(&wav, 220, 800, 400);

    printf("=== generated signal ===\n");
    printf("  sample_rate=%u channels=%u bits=%u samples=%u\n",
           wav.sample_rate, wav.channels, wav.bits_per_sample, wav.sample_count);
    wav_stats(&wav, &before);
    printf("  peak=%d minimum=%d average=%d silent=%d zero_crossings=%d\n",
           before.peak, before.minimum, before.average, before.silent_samples,
           before.zero_crossings);

    length = wav_serialize(&wav, buffer, (int)sizeof buffer);
    printf("=== riff header ===\n");
    printf("  bytes=%d riff_size=%u wave=%s fmt=%u channels=%u rate=%u bits=%u data=%u\n",
           length, (unsigned int)(buffer[4] | (buffer[5] << 8) | (buffer[6] << 16) |
                                  ((unsigned int)buffer[7] << 24)),
           (memcmp(buffer + 8, "WAVE", 4) == 0) ? "yes" : "no",
           (unsigned int)(buffer[16] | (buffer[17] << 8) | (buffer[18] << 16) |
                          ((unsigned int)buffer[19] << 24)),
           (unsigned int)(buffer[22] | (buffer[23] << 8)),
           (unsigned int)(buffer[24] | (buffer[25] << 8) | (buffer[26] << 16) |
                          ((unsigned int)buffer[27] << 24)),
           (unsigned int)(buffer[34] | (buffer[35] << 8)),
           (unsigned int)(buffer[40] | (buffer[41] << 8) | (buffer[42] << 16) |
                          ((unsigned int)buffer[43] << 24)));
    printf("  first 32 bytes:\n");
    wav_hex_dump(buffer, length, 32);

    printf("=== parse back ===\n");
    rc = wav_parse(buffer, length, &parsed);
    printf("  parse rc=%d rate=%u channels=%u bits=%u samples=%u\n", rc,
           parsed.sample_rate, parsed.channels, parsed.bits_per_sample, parsed.sample_count);
    for (i = 0; i < (int)wav.sample_count; i++) {
        if (wav.samples[i] != parsed.samples[i]) {
            same = 0;
            break;
        }
    }
    printf("  samples_identical=%s\n", same ? "yes" : "no");

    printf("=== gain of six decibels ===\n");
    wav_apply_gain(&wav, 6.0, &clipped);
    wav_stats(&wav, &after);
    printf("  peak before=%d after=%d clipped=%d\n", before.peak, after.peak, clipped);
    printf("  average before=%d after=%d\n", before.average, after.average);

    printf("=== silence detection ===\n");
    wav_detect_silence(&wav, 2, &start, &silence);
    printf("  silence start=%d length=%d\n", start, silence);

    printf("=== summary ===\n");
    printf("  total_samples=%u duration_ms=%d\n", wav.sample_count,
           (int)((long)wav.sample_count * 1000L / (long)wav.sample_rate));
    printf("  average_amplitude=%d peak=%d\n", after.average, after.peak);
    printf("=== done ===\n");
    return 0;
}
