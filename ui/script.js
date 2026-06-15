import * as pdfjsLib from "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/4.4.168/pdf.min.mjs";

pdfjsLib.GlobalWorkerOptions.workerSrc =
    "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/4.4.168/pdf.worker.min.mjs";

const pdf = await pdfjsLib.getDocument("CV.pdf").promise;

const page = await pdf.getPage(1);

const scale = 1.5;
const viewport = page.getViewport({ scale });

const canvas = document.getElementById("pdf-canvas");
const context = canvas.getContext("2d");

canvas.width = viewport.width;
canvas.height = viewport.height;

await page.render({
    canvasContext: context,
    viewport: viewport
}).promise;