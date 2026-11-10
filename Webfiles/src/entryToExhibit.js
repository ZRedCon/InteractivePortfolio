
function getHTMLFromEntry(object) {
    let exhibit = `
    <article class="exhibit">
        ${convertToHeader(object)}
        ${convertToSkills(object[ "related-skills" ])}
        ${convertToContent(object)}
        ${convertToLinks(object[ "related-links" ])}
    </article>`;

    return exhibit;
}

function convertToHeader(object) {
    return `<section class="header">
            <h2 class="entry-name">${object.name}</h2>
            <p class="date">${object.time[0]} - ${object.time[1]}</p>
        </section>`;
}

function convertToContent(object) {
    return `<section class="content"><section class="text-important">
                ${convertToDescription(object.description)}
                ${convertToContribution(object.contribution)}
            </section>
            ${convertToSlideShow(object["slide-show"], object.name)}
            ${convertToNotes(object.notes)}</section>`
}

function convertToNotes(notes) {
    let list = `<section class="text-unimportant"><h3>Notes:</h3>`;
    for (const item of notes) {
        list += `<p>${item}</p>`;
    }
    return list + `</section>`;
}

function convertToDescription(description) {
    let desc = `<section class="proj-desc"><h3>Project Description:</h3><p>${description}</p></section>`;
    return desc;
}

function convertToContribution(contributions) {
    let list = `<section class="contribution"><h3>Contributions:</h3><ul>`;
    for (const item of contributions) {
        list += `<li>${item}</li>`;
    }
    return list + `</ul></section>`;
}

function convertToLinks(links) {
    let output = `<section class="links">`;
    for (const item of links) {
        output += `<a href="${item["url"]}">${item["display-text"]}</a>`;
    }
    return output + `</section>`;
}

// The images, plus (when there's more than one) the arrows and the row of dots that marks the
// current image. slideShow.js makes them move. No images = an empty section, which CSS hides.
function convertToSlideShow(slideShow, name) {
    let output = `<section class="slide-show">`;

    for (const item of slideShow) {
        output += `<img src="assets/images/${item}.png" alt="Image for: ${name}" draggable="false">`;
    }
    if (slideShow.length > 1) {
        output += `<button class="slide-arrow prev" type="button" aria-label="Previous image"><i class="fa-solid fa-chevron-left" aria-hidden="true"></i></button>`;
        output += `<button class="slide-arrow next" type="button" aria-label="Next image"><i class="fa-solid fa-chevron-right" aria-hidden="true"></i></button>`;
        output += `<div class="slide-dots" aria-hidden="true">`;
        for (let i = 0; i < slideShow.length; i++) {
            output += i === 0 ? `<span class="current"></span>` : `<span></span>`;
        }
        output += `</div>`;
    }
    return output + `</section>`;
}

const SKILLS = [
    "Game Design",
	"Game Dev",
	"Programming",
	"Web Design & Dev",
	"Music Comp",
	"Audio Design",
	"Art",
	"UI/UX",
	"Production"
];

const SEED = 951;

function convertToSkills(skills) {
    let output = `<section class="skills">`;
    let index = 0;
    let value = skills;
    while (value > 0) {
        if (value & 1 == 1) {
            output += `<span class="skill"><div style="background-color: hsl( ${SEED * (index+1)} 100% 50%); "></div><span>${SKILLS[ index ]}</span></span>`;
        }
        index++;
        value >>= 1;
    }
    return output + `</section>`;
}



export { getHTMLFromEntry }