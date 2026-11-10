import * as ToHTML from './entryToExhibit.js'
import { SlideShow } from './slideShow.js'

const DATA_PATH = "assets/data/";
const DATA_INDEX_PATH = "assets/data-index.json";

let objects = [];

async function fetchJson(url) {
    const response = await fetch(url);
    if (!response.ok) {
        throw new Error(`${url}: ${response.status} ${response.statusText}`);
    }
    return response.json();
}

async function loadEntry(fileName) {
    try {
        return await fetchJson(DATA_PATH + fileName);
    } catch (error) {
        console.error(`Bad file at ${DATA_PATH + fileName}:`, error);
        return null;
    }
}

window.onload = async () => {
    console.log("Starting parse...");
    const fileNames = await fetchJson(DATA_INDEX_PATH);
    // Downloads every file at once; the results keep the index's order.
    const entries = await Promise.all(fileNames.map(loadEntry));
    objects = entries.filter((entry) => entry !== null);
    console.log("Parsed objects: ", objects);
    const exhibits = document.querySelector("#exhibits");
    for (const item of objects) {
        let conversion = ToHTML.getHTMLFromEntry( item );
        // Adds the exhibit after the others without rebuilding them. (innerHTML += rebuilds every
        // exhibit already there, and the rebuilt slideshows would lose their clicks and drags.)
        exhibits.insertAdjacentHTML("beforeend", conversion);
        new SlideShow(exhibits.lastElementChild.querySelector(".slide-show"));
    }
};
