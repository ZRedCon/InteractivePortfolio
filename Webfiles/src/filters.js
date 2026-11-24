const MASK_MAX = 511;
let mask = MASK_MAX;
let ageMode = "newest";

let newest, oldest;
let skillButtons;
let all, clear;
let updateCallback;

function initUI() {
    newest = document.querySelector("#newest");
    oldest = document.querySelector("#oldest");
    all = document.querySelector("#all");
    clear = document.querySelector("#none");

    newest.addEventListener("click", () => {
        ageMode = "newest";
        setButtonToggleState(newest, false);
        setButtonToggleState(oldest, true);
        updateCallback();
    });
    oldest.addEventListener("click", () => {
        ageMode = "oldest";
        setButtonToggleState(newest, true);
        setButtonToggleState(oldest, false);
        updateCallback();
    });
    all.addEventListener("click", () => {
        skillButtons.forEach(element => {
            setButtonToggleState(element, false);
        });
        mask = MASK_MAX;
        verifyMask();
    });
    clear.addEventListener("click", () => {       
        skillButtons.forEach(element => {
            setButtonToggleState(element, true);
        });
        mask = 0;
        verifyMask();
    });

    skillButtons = document.querySelector("#skill-buttons").querySelectorAll("button");
    skillButtons.forEach( (e, index) => {
        e.addEventListener("click", () => { 
            flipSkillMaskBit(Math.pow(2, index));
            toggleButton(e);
            verifyMask();
        });
    });
}

function verifyMask() {
    setButtonToggleState(clear, true);
    setButtonToggleState(all, true);
    if (mask == 0)
        setButtonToggleState(clear, false);
    else if (mask == MASK_MAX)
        setButtonToggleState(all, false);

    updateCallback();
}

function flipSkillMaskBit(bitNum) {
    mask ^= bitNum;
    console.log(mask);
}

function setButtonToggleState(button, boolState) {
    if (button.classList.contains("no-double-tap"))
        button.disabled = !boolState;
    if (boolState)
        button.classList.replace("btn-off", "btn-on");
    else
        button.classList.replace("btn-on", "btn-off");
}

function toggleButton(button) {
    setButtonToggleState(button, !button.classList.contains("btn-on"))
}

function getFilterSkills() {
    return mask;
}

function getAgeMode() {
    return ageMode;
}

function setCallback(callback) {
    updateCallback = callback;
}

export { initUI, getFilterSkills, getAgeMode, setCallback }