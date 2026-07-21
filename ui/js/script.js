async function updateViewCount() {
    const response = await fetch(`${window.APP_CONFIG.apiBaseUrl}views`, {
        method: "POST"
    });

    const data = await response.json();

    document.getElementById("view-count").textContent = data.view_count;
}

const subscribeForm = document.getElementById("subscribe-form");
const subscribeStatus = document.getElementById("subscribe-status");

subscribeForm.addEventListener("submit", async (event) => {
    event.preventDefault();

    const emailInput = document.getElementById("subscriber-email");
    const submitButton = subscribeForm.querySelector("button");

    subscribeStatus.textContent = "";
    submitButton.disabled = true;

    try {
        const response = await fetch(`${apiBaseUrl}/subscribe`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json"
            },
            body: JSON.stringify({
                email: emailInput.value
            })
        });

        const result = await response.json();

        if (!response.ok) {
            throw new Error(result.message || "Subscription failed");
        }

        subscribeStatus.textContent = result.message;
        subscribeForm.reset();
    } catch (error) {
        subscribeStatus.textContent = error.message;
    } finally {
        submitButton.disabled = false;
    }
});

updateViewCount();