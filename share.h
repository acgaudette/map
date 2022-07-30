#ifdef GL
	#define RGB(R, G, B) (vec3( (R) / 255.f, (G) / 255.f, (B) / 255.f ))
#else
	#define RGB(R, G, B) ((v3) { (R) / 255.f, (G) / 255.f, (B) / 255.f })
#endif

#ifdef PALETTE_LIGHT
	#define COL_TEXT RGB(0, 140, 160)
	#define COL_EDGE RGB(210, 210, 210)
	#define COL_HIL  RGB(255, 255, 40)
	#define COL_SEL  RGB(0, 80, 80)
	#define COL_EDIT RGB(100, 200, 100)
	#define COL_TABLE RGB(255, 255, 255)
	#define COL_ERR RGB(255, 10, 0)
#else // Dark
	#define COL_TEXT RGB(255, 255, 255)
	#define COL_EDGE RGB(140, 160, 180)
	#define COL_HIL  RGB(0, 255, 255)
	#define COL_SEL  RGB(255, 255, 0)
	#define COL_EDIT RGB(255, 0, 0)
	#define COL_TABLE RGB(3, 25, 39)
	#define COL_ERR RGB(240, 210, 110)
#endif
