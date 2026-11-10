/* =============================================================================
   One exhibit's slideshow. convertToSlideShow (entryToExhibit.js) writes the
   markup, and this class makes it move. The Godot game has the same slideshow
   in GodotProject/interactive-portfolio/prefabs/slide_show.gd, so a change here
   usually belongs there too.
   ============================================================================= */

const SECONDS_PER_SLIDE = 5;        // how long each image stays before sliding to the next
const SLIDE_SECONDS = 0.4;          // how long one slide animation takes
const DRAG_SWITCH_FRACTION = 0.25;  // dragging further than this much of the width switches images

// Visitors who've asked their system for less motion get instant switches instead of slides.
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

const wrap = (index, count) => ((index % count) + count) % count;
const clamp = (value, min, max) => Math.min(Math.max(value, min), max);

class SlideShow {
    constructor(section) {
        this.section = section;
        this.slides = [...section.querySelectorAll("img")];
        this.dots = [...section.querySelectorAll(".slide-dots span")];
        this.current = 0;
        // Where the current image sits, in image widths: 0 = in the frame, 1 = one full width
        // to the right. Switching images starts the new one off to the side it comes from,
        // then eases this back to 0.
        this.offset = 0;
        this.animationFrame = 0;
        this.drag = null;
        this.timeout = 0;
        this.timerEnds = 0;
        this.timeLeft = 0;

        if (this.slides.length < 2) return;     // one image (or none): nothing to rotate
        section.querySelector(".slide-arrow.prev").addEventListener("click", () => this.go(-1));
        section.querySelector(".slide-arrow.next").addEventListener("click", () => this.go(1));
        section.addEventListener("pointerdown", (event) => this.startDrag(event));
        section.addEventListener("pointermove", (event) => this.moveDrag(event));
        // pointercancel: the browser took over, e.g. to scroll the page on a phone.
        for (const type of ["pointerup", "pointercancel", "lostpointercapture"]) {
            section.addEventListener(type, (event) => this.endDrag(event));
        }
        this.placeSlides();
        this.restartTimer();
    }

    // ---- Moving between images ------------------------------------------------

    // Switches to the image beside the current one: 1 = the one to the right, -1 = the one to the left.
    go(direction) {
        this.current = wrap(this.current + direction, this.slides.length);
        this.offset = clamp(this.offset + direction, -1, 1);    // the new image starts off to that side,
        this.slideHome();                                       // then slides into the frame
        this.dots.forEach((dot, i) => dot.classList.toggle("current", i === this.current));
        this.restartTimer();                                    // the new image gets its full time
    }

    // Eases offset back to 0 (ease-out cubic, same curve as the Godot tween).
    slideHome() {
        cancelAnimationFrame(this.animationFrame);
        if (reducedMotion.matches) {
            this.offset = 0;
            this.placeSlides();
            return;
        }
        const from = this.offset;
        const start = performance.now();
        const step = (now) => {
            const t = clamp((now - start) / (SLIDE_SECONDS * 1000), 0, 1);
            this.offset = from * (1 - t) ** 3;
            this.placeSlides();
            if (t < 1) this.animationFrame = requestAnimationFrame(step);
        };
        this.animationFrame = requestAnimationFrame(step);
    }

    // Puts the current image `offset` widths from the middle and, while it's off center, the image
    // beside it in the gap it leaves. All the others are hidden.
    placeSlides() {
        const side = this.offset > 0 ? -1 : 1;     // the neighbor that's coming into view
        const neighbor = this.offset !== 0 ? wrap(this.current + side, this.slides.length) : this.current;
        this.slides.forEach((img, i) => {
            const at = i === this.current ? this.offset : i === neighbor ? this.offset + side : null;
            img.style.visibility = at === null ? "hidden" : "visible";
            img.style.transform = at === null ? "" : `translateX(${at * 100}%)`;
        });
    }

    // ---- Timer: setTimeout can't pause, so pausing remembers the time left ------

    restartTimer() {
        this.startTimer(SECONDS_PER_SLIDE * 1000);
    }

    startTimer(milliseconds) {
        clearTimeout(this.timeout);
        this.timerEnds = performance.now() + milliseconds;
        this.timeout = setTimeout(() => this.go(1), milliseconds);
    }

    pauseTimer() {
        clearTimeout(this.timeout);
        this.timeLeft = Math.max(this.timerEnds - performance.now(), 0);
    }

    resumeTimer() {
        this.startTimer(this.timeLeft);
    }

    // ---- Click and drag ---------------------------------------------------------
    // Holding the mouse (or a finger) down on the images lets you pull them sideways.
    // The timer waits while you hold.

    startDrag(event) {
        if (this.drag || event.button !== 0 || event.target.closest(".slide-arrow")) return;
        cancelAnimationFrame(this.animationFrame);     // catches the images wherever they are, even mid-slide
        this.pauseTimer();
        this.drag = {
            pointerId: event.pointerId,
            startX: event.clientX,
            startOffset: this.offset,
            width: this.section.clientWidth,
        };
        // Keeps the drag going even when the pointer leaves the slideshow.
        this.section.setPointerCapture(event.pointerId);
        this.section.classList.add("dragging");
    }

    moveDrag(event) {
        if (event.pointerId !== this.drag?.pointerId) return;
        const moved = (event.clientX - this.drag.startX) / this.drag.width;
        this.offset = clamp(this.drag.startOffset + moved, -1, 1);
        this.placeSlides();
    }

    endDrag(event) {
        if (event.pointerId !== this.drag?.pointerId) return;
        const moved = this.offset - this.drag.startOffset;
        this.drag = null;
        this.section.classList.remove("dragging");
        // Pulled far enough, toward the image coming into view: switch to it (which resets the timer).
        if (Math.abs(this.offset) > DRAG_SWITCH_FRACTION && Math.sign(moved) === Math.sign(this.offset)) {
            this.go(this.offset > 0 ? -1 : 1);
        } else {    // otherwise slide back, and the timer carries on from where it paused
            this.slideHome();
            this.resumeTimer();
        }
    }
}

export { SlideShow }
