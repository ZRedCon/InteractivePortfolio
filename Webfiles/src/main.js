import * as ToHTML from './entryToExhibit.js'

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
    for (const item of objects) {
        let conversion = ToHTML.getHTMLFromEntry( item );
        document.querySelector("#exhibits").innerHTML += conversion;
    }
};
