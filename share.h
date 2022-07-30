#ifdef GL
	#define RGB(R, G, B) (vec3( (R) / 255.f, (G) / 255.f, (B) / 255.f ))
#else
	#define RGB(R, G, B) ((v3) { (R) / 255.f, (G) / 255.f, (B) / 255.f })
#endif

#define COL_TABLE RGB(3, 25, 39)
#define COL_ERR RGB(240, 210, 110)
