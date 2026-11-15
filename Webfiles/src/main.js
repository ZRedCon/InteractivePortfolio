import * as ToHTML from './entryToExhibit.js'
import { SlideShow } from './slideShow.js'

const DATA_PATH = "assets/data/";
const DATA_INDEX_PATH = "assets/data-index.json";

let objects = [];
let newestFirst = [];

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
    const entries = await Promise.all(fileNames.map(loadEntry));
    objects = entries.filter((entry) => entry !== null);
    console.log("Parsed objects: ", objects);
    const exhibits = document.querySelector("#exhibits");

    newestFirst = orderNewestFirst();

    for (const item of newestFirst) {
        let conversion = ToHTML.getHTMLFromEntry( item );
        exhibits.insertAdjacentHTML("beforeend", conversion);
        new SlideShow(exhibits.lastElementChild.querySelector(".slide-show"));
    }
};

function orderNewestFirst() {
    let orderedObjects = [];
    let dates = []

    // Get the dates as numbers YYYYMMDD
    for (const object of objects) {
        let dateNum = 0;
        let endDate = (object["time"])[1];
        if (endDate == "Ongoing") 
            endDate = (object["time"])[0];

        // Number() so "+ day" adds instead of gluing strings together
        let values = endDate.split("/").map(Number);
        let year = values.at(-1);
        let month = values.length >= 2 ? values[0] : 0;
        let day = values.length == 3 ? values[1] : 0;
        dateNum = 10000 * year + 100 * month + day;
        dates.push(dateNum);
    }
    let pool = [...objects];

    // O(n^2) time, I do not have time to find a faster solution!
    while (pool.length > 0) {
        // Reset every pass: last pass's highest value was just removed
        let optimalIndex = 0;
        let optimalValue = -1;
        dates.forEach((item, index) => {
            if (item > optimalValue) {
                optimalValue = item;
                optimalIndex = index;
            }
        });

        dates.splice(optimalIndex, 1);
        let entry = pool.splice(optimalIndex, 1)
        orderedObjects.push(entry[0]);
    }

    return orderedObjects;
}