#define INPUT_WIDTH 256
#define INPUT_HEIGHT 344
#define ACTIVE_HEIGHT 192

#define OUT_WIDTH 192
#define OUT_HEIGHT 256

unsigned short input_buffer[INPUT_HEIGHT * INPUT_WIDTH];
unsigned char output_buffer[OUT_HEIGHT * OUT_WIDTH * 3];

typedef struct {
    float pos;
    unsigned char r;
    unsigned char g;
    unsigned char b;
} Anchor;

Anchor anchors[] = {
    {0.00f, 0, 0, 10},
    {0.15f, 20, 0, 90},
    {0.30f, 90, 0, 120},
    {0.45f, 180, 0, 100},
    {0.60f, 230, 60, 20},
    {0.75f, 250, 150, 0},
    {0.90f, 250, 220, 100},
    {1.00f, 255, 255, 255}
};
#define NUM_ANCHORS 8

unsigned char lut_r[256];
unsigned char lut_g[256];
unsigned char lut_b[256];

void init_lut() {
    for (int i = 0; i < 256; i++) {
        float val = i / 255.0f;
        for (int k = 0; k < NUM_ANCHORS - 1; k++) {
            float x0 = anchors[k].pos;
            float x1 = anchors[k+1].pos;
            if (val >= x0 && val <= x1) {
                float t = (val - x0) / (x1 - x0);
                lut_r[i] = (unsigned char)(anchors[k].r + t * (anchors[k+1].r - anchors[k].r));
                lut_g[i] = (unsigned char)(anchors[k].g + t * (anchors[k+1].g - anchors[k].g));
                lut_b[i] = (unsigned char)(anchors[k].b + t * (anchors[k+1].b - anchors[k].b));
                break;
            }
        }
    }
}

void process_frame() {
    unsigned short p_min = 65535;
    unsigned short p_max = 0;
    
    int active_size = ACTIVE_HEIGHT * INPUT_WIDTH;
    for (int i = 0; i < active_size; i++) {
        unsigned short val = input_buffer[i];
        if (val < p_min) p_min = val;
        if (val > p_max) p_max = val;
    }
    
    float diff = p_max - p_min;
    if (diff == 0.0f) diff = 1.0f;
    
    for (int x = 0; x < OUT_HEIGHT; x++) {
        for (int y = 0; y < OUT_WIDTH; y++) {
            unsigned short raw_val = input_buffer[y * INPUT_WIDTH + x];
            float norm = (raw_val - p_min) / diff;
            int idx = (int)(norm * 255.0f);
            if (idx < 0) idx = 0;
            if (idx > 255) idx = 255;
            
            int out_idx = (x * OUT_WIDTH + y) * 3;
            output_buffer[out_idx] = lut_r[idx];
            output_buffer[out_idx + 1] = lut_g[idx];
            output_buffer[out_idx + 2] = lut_b[idx];
        }
    }
}

void* get_input_ptr() { return input_buffer; }
void* get_output_ptr() { return output_buffer; }
