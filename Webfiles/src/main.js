let objects = [];

window.onload = () => {
    const url = "assets/data/game-example.json";
    const xhr = new XMLHttpRequest();
    xhr.onload = (e) => {
        console.log("Starting parse...");
        const json = JSON.parse(e.target.responseText);
        objects.push(json);
    }
    xhr.open("GET", url);
    xhr.send();
    console.log("DONE!");
};