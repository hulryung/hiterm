// Smooth scroll shader: offsets the rendered content by the pending scroll amount.
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragCoord -= iPendingScroll;
    fragColor = texture(iChannel0, fragCoord / iResolution.xy);
}
