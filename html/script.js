const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'rp_crafting';

const state = {
    visible: false,
    adminVisible: false,
    station: null,
    recipes: [],
    recipeMap: {},
    queue: [],
    blueprints: [],
    admin: {
        stations: {},
        recipes: {}
    },
    settings: {
        minigame: true,
        animations: true,
        durability: true,
        fees: true
    }
};

const root = document.getElementById('root');
const admin = document.getElementById('admin');
const progressBox = document.getElementById('progress');
const progressValue = progressBox.querySelector('.progress-value');
const progressLabel = document.getElementById('progress-label');
const minigame = document.getElementById('minigame');
const cursor = minigame.querySelector('.cursor');
const target = minigame.querySelector('.target');
const minigameButton = document.getElementById('minigame-button');
const searchInput = document.getElementById('search');
const closeBtn = document.getElementById('close-btn');
const cancelCraftBtn = document.getElementById('cancel-craft');
const adminCloseBtn = document.getElementById('admin-close');

let currentRecipeId = null;
let minigameActive = false;
let cursorDirection = 1;
let cursorPosition = 0;
let cursorInterval;

function post(action, data = {}) {
    fetch(`https://${resource}/${action}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
    });
}

function setVisible(element, toggle) {
    element.classList.toggle('hidden', !toggle);
}

function setActiveTab(container, tab) {
    container.querySelectorAll('.tabs button').forEach((btn) => {
        btn.classList.toggle('active', btn.dataset.tab === tab);
    });
    container.querySelectorAll('main .tab').forEach((section) => {
        section.classList.toggle('active', section.id === `tab-${tab}`);
    });
}

function formatRequirement(label, value) {
    return `<strong>${label}:</strong> ${value}`;
}

function renderBlueprints() {
    const wrapper = document.getElementById('blueprint-list');
    wrapper.innerHTML = '';
    const blueprints = new Set();
    Object.values(state.recipeMap).forEach((recipe) => {
        if (recipe.blueprint) {
            blueprints.add(recipe.blueprint);
        }
    });
    if (blueprints.size === 0) {
        wrapper.innerHTML = '<div class="placeholder">No blueprints required.</div>';
        return;
    }
    blueprints.forEach((name) => {
        const card = document.createElement('div');
        card.className = 'blueprint-card';
        card.innerHTML = `<h4>${name}</h4><p>Collect this item to unlock related recipes.</p>`;
        wrapper.appendChild(card);
    });
}

function recipeMatchesSearch(recipe) {
    const term = searchInput.value.trim().toLowerCase();
    if (!term) return true;
    return recipe.label.toLowerCase().includes(term) || recipe.id.toLowerCase().includes(term);
}

function renderRecipeList() {
    const list = document.getElementById('recipe-list');
    list.innerHTML = '';
    const filtered = state.recipes.filter(recipeMatchesSearch);
    if (filtered.length === 0) {
        list.innerHTML = '<div class="placeholder">No recipes found.</div>';
        return;
    }

    filtered.forEach((recipe) => {
        const card = document.createElement('div');
        card.className = 'card';
        if (recipe.id === currentRecipeId) card.classList.add('active');
        const iconLabel = (recipe.icon || recipe.label || recipe.id || '?').toString().trim();
        const iconText = iconLabel ? iconLabel.charAt(0).toUpperCase() : '?';
        card.innerHTML = `
            <div class="item-header">
                <div class="item-icon" aria-hidden="true">${iconText}</div>
                <div>
                    <h3>${recipe.label}</h3>
                    <p>${recipe.time / 1000}s • ${recipe.station}</p>
                </div>
            </div>
            <div class="meta">${recipe.tools && recipe.tools.length ? `Tools: ${recipe.tools.join(', ')}` : 'No tools required'}</div>
        `;
        card.addEventListener('click', () => {
            currentRecipeId = recipe.id;
            renderRecipeList();
            renderRecipeDetails(recipe);
            post('crafting:sfx', { sound: 'open' });
        });
        list.appendChild(card);
    });
}

function renderRecipeDetails(recipe) {
    const panel = document.getElementById('recipe-details');
    if (!recipe) {
        panel.innerHTML = '<div class="placeholder">Select a recipe to view details.</div>';
        return;
    }

    const inputs = (recipe.inputs || []).map((input) => `<li>${input.count}x ${input.item}</li>`).join('');
    const outputs = (recipe.outputs || []).map((output) => `<li>${output.count}x ${output.item}</li>`).join('');
    const requirements = [];
    if (recipe.job) requirements.push(formatRequirement('Job', recipe.job));
    if (recipe.grade) requirements.push(formatRequirement('Grade', recipe.grade));
    if (recipe.blueprint) requirements.push(formatRequirement('Blueprint', recipe.blueprint));
    if (recipe.accountMoney) requirements.push(formatRequirement('Account', `${recipe.accountMoney.account} $${recipe.accountMoney.amount}`));
    if (recipe.fee) requirements.push(formatRequirement('Fee', `$${recipe.fee}`));
    if (recipe.cooldown) requirements.push(formatRequirement('Cooldown', `${recipe.cooldown}s`));

    panel.innerHTML = `
        <div class="recipe-header">
            <h2>${recipe.label}</h2>
            <p>${recipe.description || 'Craft this item using the required materials.'}</p>
        </div>
        <div class="requirements">
            <h3>Inputs</h3>
            <ul>${inputs || '<li>None</li>'}</ul>
        </div>
        <div class="requirements">
            <h3>Outputs</h3>
            <ul>${outputs || '<li>None</li>'}</ul>
        </div>
        <div class="requirements">
            <h3>Requirements</h3>
            <ul>${requirements.length ? requirements.map((r) => `<li>${r}</li>`).join('') : '<li>None</li>'}</ul>
        </div>
        <div class="actions">
            <label>Amount <input id="craft-amount" type="number" min="1" value="1" /></label>
            <button id="craft-button">Queue Craft</button>
        </div>
    `;

    document.getElementById('craft-button').addEventListener('click', () => {
        const amount = parseInt(document.getElementById('craft-amount').value, 10) || 1;
        post('crafting:add', { recipeId: recipe.id, amount });
    });
}

function renderQueue() {
    const wrapper = document.getElementById('queue-list');
    wrapper.innerHTML = '';
    if (!state.queue || state.queue.length === 0) {
        wrapper.innerHTML = '<div class="placeholder">Queue is empty.</div>';
        return;
    }
    state.queue.forEach((entry, index) => {
        const recipe = state.recipeMap[entry.recipeId];
        const card = document.createElement('div');
        card.className = 'queue-item';
        card.innerHTML = `
            <div>
                <strong>${index === 0 ? 'Current' : 'Queued'}:</strong> ${recipe ? recipe.label : entry.recipeId}
            </div>
            <div>Amount: ${entry.amount}</div>
        `;
        wrapper.appendChild(card);
    });
}

function renderStationDetails(station) {
    const wrapper = document.getElementById('station-details');
    if (!station) {
        wrapper.innerHTML = '<div class="placeholder">Select or create a station.</div>';
        return;
    }
    wrapper.innerHTML = `
        <form id="station-form" class="details-form">
            <label>ID <input name="id" value="${station.id || ''}" ${station.id ? 'readonly' : ''} /></label>
            <label>Label <input name="label" value="${station.label || ''}" required /></label>
            <label>Type <input name="type" value="${station.type || ''}" required /></label>
            <label>Coords <input name="coords" value="${(station.coords || []).join(', ')}" placeholder="x, y, z" required /></label>
            <label>Radius <input name="radius" type="number" step="0.1" value="${station.radius || 2.0}" /></label>
            <label>Job <input name="job" value="${station.job || ''}" /></label>
            <label>Grade <input name="grade" type="number" value="${station.grade || 0}" /></label>
            <label>Items <input name="items" value="${(station.items || []).join(',')}" placeholder="item_a,item_b" /></label>
            <label>Hours <input name="hours" value="${station.hours ? `${station.hours.open},${station.hours.close}` : ''}" placeholder="open,close" /></label>
            <div class="form-actions">
                <button type="submit">Save</button>
                ${station.id ? '<button type="button" id="delete-station" class="danger">Delete</button>' : ''}
            </div>
        </form>
    `;

    const form = document.getElementById('station-form');
    form.addEventListener('submit', (e) => {
        e.preventDefault();
        const data = new FormData(form);
        const payload = {
            id: station.id || data.get('id'),
            label: data.get('label'),
            type: data.get('type'),
            coords: data.get('coords').split(',').map((v) => Number(v.trim())),
            radius: Number(data.get('radius')),
            job: data.get('job') !== '' ? data.get('job') : null,
            grade: Number(data.get('grade')),
            items: data.get('items') ? data.get('items').split(',').map((v) => v.trim()).filter(Boolean) : [],
            hours: data.get('hours') ? (() => {
                const [open, close] = data.get('hours').split(',').map((v) => Number(v.trim()));
                return { open, close };
            })() : null
        };
        post('crafting:admin:saveStation', payload);
    });

    const deleteBtn = document.getElementById('delete-station');
    if (deleteBtn) {
        deleteBtn.addEventListener('click', () => {
            if (confirm('Delete this station?')) {
                post('crafting:admin:deleteStation', { id: station.id });
            }
        });
    }
}

function renderRecipeAdminForm(recipe) {
    const wrapper = document.getElementById('admin-recipe-details');
    if (!recipe) {
        wrapper.innerHTML = '<div class="placeholder">Select or create a recipe.</div>';
        return;
    }
    wrapper.innerHTML = `
        <form id="admin-recipe-form" class="details-form">
            <label>ID <input name="id" value="${recipe.id || ''}" ${recipe.id ? 'readonly' : ''} /></label>
            <label>Label <input name="label" value="${recipe.label || ''}" required /></label>
            <label>Station Type <input name="station" value="${recipe.station || ''}" required /></label>
            <label>Inputs <textarea name="inputs" placeholder='[{"item":"iron","count":1}]'>${JSON.stringify(recipe.inputs || [])}</textarea></label>
            <label>Outputs <textarea name="outputs" placeholder='[{"item":"weapon","count":1}]'>${JSON.stringify(recipe.outputs || [])}</textarea></label>
            <label>Time (ms) <input name="time" type="number" value="${recipe.time || 5000}" /></label>
            <label>Tools <input name="tools" value="${(recipe.tools || []).join(',')}" /></label>
            <label>Job <input name="job" value="${recipe.job || ''}" /></label>
            <label>Grade <input name="grade" type="number" value="${recipe.grade || 0}" /></label>
            <label>Cooldown <input name="cooldown" type="number" value="${recipe.cooldown || 0}" /></label>
            <label>Fee <input name="fee" type="number" value="${recipe.fee || 0}" /></label>
            <label>Blueprint <input name="blueprint" value="${recipe.blueprint || ''}" /></label>
            <div class="form-actions">
                <button type="submit">Save</button>
                ${recipe.id ? '<button type="button" id="delete-recipe" class="danger">Delete</button>' : ''}
            </div>
        </form>
    `;

    const form = document.getElementById('admin-recipe-form');
    form.addEventListener('submit', (e) => {
        e.preventDefault();
        try {
            const data = new FormData(form);
            const payload = {
                id: recipe.id || data.get('id'),
                label: data.get('label'),
                station: data.get('station'),
                inputs: JSON.parse(data.get('inputs') || '[]'),
                outputs: JSON.parse(data.get('outputs') || '[]'),
                time: Number(data.get('time')),
                tools: data.get('tools') ? data.get('tools').split(',').map((v) => v.trim()).filter(Boolean) : [],
                job: data.get('job') || null,
                grade: Number(data.get('grade')),
                cooldown: Number(data.get('cooldown')),
                fee: Number(data.get('fee')),
                blueprint: data.get('blueprint') || null
            };
            post('crafting:admin:saveRecipe', payload);
        } catch (err) {
            console.error(err);
            alert('Invalid JSON in inputs or outputs');
        }
    });

    const deleteBtn = document.getElementById('delete-recipe');
    if (deleteBtn) {
        deleteBtn.addEventListener('click', () => {
            if (confirm('Delete this recipe?')) {
                post('crafting:admin:deleteRecipe', { id: recipe.id });
            }
        });
    }
}

function renderAdminLists() {
    const stationList = document.getElementById('station-list');
    stationList.innerHTML = '';
    const addStationCard = document.createElement('div');
    addStationCard.className = 'card';
    addStationCard.innerHTML = '<h3>+ Create Station</h3><p>Setup a new crafting station.</p>';
    addStationCard.addEventListener('click', () => renderStationDetails({}));
    stationList.appendChild(addStationCard);

    Object.values(state.admin.stations).forEach((station) => {
        const card = document.createElement('div');
        card.className = 'card';
        card.innerHTML = `<h3>${station.label}</h3><p>${station.type} • radius ${station.radius}</p>`;
        card.addEventListener('click', () => renderStationDetails(station));
        stationList.appendChild(card);
    });

    const recipeList = document.getElementById('admin-recipe-list');
    recipeList.innerHTML = '';
    const addRecipeCard = document.createElement('div');
    addRecipeCard.className = 'card';
    addRecipeCard.innerHTML = '<h3>+ Create Recipe</h3><p>Define a new crafting recipe.</p>';
    addRecipeCard.addEventListener('click', () => renderRecipeAdminForm({}));
    recipeList.appendChild(addRecipeCard);

    Object.values(state.admin.recipes).forEach((recipe) => {
        const card = document.createElement('div');
        card.className = 'card';
        card.innerHTML = `<h3>${recipe.label}</h3><p>${recipe.station} • ${recipe.time / 1000}s</p>`;
        card.addEventListener('click', () => renderRecipeAdminForm(recipe));
        recipeList.appendChild(card);
    });
}

function updateSettingsUI() {
    ['minigame', 'animations', 'durability', 'fees'].forEach((key) => {
        const element = document.getElementById(`setting-${key}`);
        if (element) {
            element.checked = !!state.settings[key];
        }
    });
}

function handleMessage(event) {
    const data = event.data;
    switch (data.action) {
        case 'open': {
            const firstOpen = !state.visible;
            state.visible = true;
            state.station = data.station;
            document.getElementById('menu-title').textContent = data.station.label;
            document.getElementById('menu-subtitle').textContent = `Type: ${data.station.type}`;
            state.recipes = data.recipes || [];
            state.recipeMap = {};
            state.recipes.forEach((recipe) => { state.recipeMap[recipe.id] = recipe; });
            state.queue = data.queue || [];
            renderRecipeList();
            if (firstOpen) {
                currentRecipeId = null;
                renderRecipeDetails(null);
            } else if (currentRecipeId && state.recipeMap[currentRecipeId]) {
                renderRecipeDetails(state.recipeMap[currentRecipeId]);
            }
            renderQueue();
            renderBlueprints();
            setVisible(root, true);
            setActiveTab(root, 'recipes');
            if (firstOpen) {
                post('crafting:sfx', { sound: 'open' });
            }
            break;
        }
        case 'close': {
            state.visible = false;
            setVisible(root, false);
            state.adminVisible = false;
            setVisible(admin, false);
            break;
        }
        case 'queue': {
            state.queue = data.queue || [];
            renderQueue();
            break;
        }
        case 'progress': {
            if (data.state === 'start') {
                progressLabel.textContent = `Crafting ${data.label} x${data.amount}`;
                progressValue.style.width = '0%';
                setVisible(progressBox, true);
            } else if (data.state === 'update') {
                progressValue.style.width = `${Math.floor((data.value || 0) * 100)}%`;
            } else if (data.state === 'finish') {
                setVisible(progressBox, false);
                if (data.success) {
                    post('crafting:sfx', { sound: 'success' });
                }
            }
            break;
        }
        case 'minigame': {
            if (data.state === 'start') {
                startMinigame();
            } else if (data.state === 'success' || data.state === 'fail') {
                stopMinigame();
            }
            break;
        }
        case 'openAdmin': {
            state.adminVisible = true;
            state.admin.stations = data.stations || {};
            state.admin.recipes = data.recipes || {};
            renderAdminLists();
            renderStationDetails(null);
            renderRecipeAdminForm(null);
            updateSettingsUI();
            setActiveTab(admin, 'admin-stations');
            setVisible(admin, true);
            break;
        }
        case 'syncAdmin': {
            state.admin.stations = data.stations || {};
            state.admin.recipes = data.recipes || {};
            renderAdminLists();
            break;
        }
        case 'settings': {
            state.settings = { ...state.settings, ...data.payload };
            updateSettingsUI();
            break;
        }
        default:
            break;
    }
}

function startMinigame() {
    state.settings.minigame = true;
    const width = Math.random() * 20 + 15;
    const left = Math.random() * (80 - width) + 10;
    target.style.width = `${width}%`;
    target.style.left = `${left}%`;
    cursorPosition = 0;
    cursorDirection = 1;
    minigame.classList.add('active');
    minigameActive = true;
    cursorInterval = setInterval(() => {
        cursorPosition += cursorDirection * 1.5;
        if (cursorPosition >= 90) {
            cursorPosition = 90;
            cursorDirection = -1;
        } else if (cursorPosition <= 0) {
            cursorPosition = 0;
            cursorDirection = 1;
        }
        cursor.style.left = `${cursorPosition}%`;
    }, 16);
}

function stopMinigame() {
    minigameActive = false;
    clearInterval(cursorInterval);
    minigame.classList.remove('active');
}

minigameButton.addEventListener('click', () => {
    if (!minigameActive) return;
    const cursorCenter = cursorPosition + 5;
    const targetLeft = parseFloat(target.style.left) || 0;
    const targetRight = targetLeft + (parseFloat(target.style.width) || 25);
    const success = cursorCenter >= targetLeft && cursorCenter <= targetRight;
    post('crafting:minigame:result', { success });
});

searchInput.addEventListener('input', renderRecipeList);
closeBtn.addEventListener('click', () => post('crafting:close'));
cancelCraftBtn.addEventListener('click', () => post('crafting:cancel'));
adminCloseBtn.addEventListener('click', () => {
    state.adminVisible = false;
    setVisible(admin, false);
    post('crafting:close');
});

admin.querySelectorAll('.tabs button').forEach((button) => {
    button.addEventListener('click', () => {
        setActiveTab(admin, button.dataset.tab);
    });
});

root.querySelectorAll('.tabs button').forEach((button) => {
    button.addEventListener('click', () => {
        setActiveTab(root, button.dataset.tab);
    });
});

cancelCraftBtn.addEventListener('mouseenter', () => post('crafting:sfx', { sound: 'close' }));

Array.from(document.querySelectorAll('[data-export]')).forEach((button) => {
    button.addEventListener('click', () => {
        post('crafting:admin:export', { type: button.dataset.export });
    });
});

Array.from(document.querySelectorAll('[data-import]')).forEach((button) => {
    button.addEventListener('click', () => {
        const payload = document.getElementById('import-json').value;
        post('crafting:admin:import', { type: button.dataset.import, payload });
    });
});

['setting-minigame', 'setting-animations', 'setting-durability', 'setting-fees'].forEach((id) => {
    document.getElementById(id).addEventListener('change', (event) => {
        const key = id.split('-')[1];
        state.settings[key] = event.target.checked;
        post('crafting:admin:updateSetting', {
            minigame: document.getElementById('setting-minigame').checked,
            animations: document.getElementById('setting-animations').checked,
            durability: document.getElementById('setting-durability').checked,
            fees: document.getElementById('setting-fees').checked
        });
    });
});

window.addEventListener('message', handleMessage);

window.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
        if (state.adminVisible) {
            setVisible(admin, false);
            post('crafting:close');
        } else if (state.visible) {
            post('crafting:close');
        }
    }
});
