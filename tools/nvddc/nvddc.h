int  nvddc_open(void);              // 0 = an external DDC display is ready
void nvddc_close(void);
int  nvddc_get(int *cur, int *max); // VCP 0x10 brightness
int  nvddc_set(int value);
