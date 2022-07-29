name = map

all: $(name) assets/vert.spv assets/frag.spv assets/font.pbm
clean:
	rm -f $(name) *.o assets/frag.spv impl.h*

$(name): $(name).o
	clang $< \
	-L. -lm -ltxtquad \
	-rpath . \
	-o $@

$(name).o: main.c impl.h share.h
	clang -Werror -O0 -ggdb \
	-DWATCH \
	-I. \
	-c $< -o $@

impl.h: impl.sl
	sl $< > $@~
	mv $@~ $@

assets/frag.spv: sprite.frag share.h
	glslc $< -o $@
