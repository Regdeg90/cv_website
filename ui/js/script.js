async function updateViewCount() {
    const response = await fetch(`${window.APP_CONFIG.apiBaseUrl}views`, {
        method: "POST"
    });

    const data = await response.json();

    document.getElementById("view-count").textContent = data.view_count;
}

updateViewCount();