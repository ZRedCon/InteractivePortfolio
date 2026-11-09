
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
        output += `<a href="${item["url"]}">${item["display-test"]}</a>`;
    }
    return output + `</section>`;
}

//TODO
function convertToSlideShow(slideShow, name) {
    let output = `<section class="slide-show">`;

    for (const item of slideShow) {
        output += `
        <img src="assets/images/${item}.png" alt="Image for: ${name}">`;
    }
    console.log(output);
    //return `<section class="slide-show"><img src="assets/images/${slideShow[0]}.png" alt="Placeholder: magenta and black checkerboard"></section>`;
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