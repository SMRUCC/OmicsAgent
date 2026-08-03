!function ($) {
    $(function () {
        window.prettyPrint && prettyPrint()
    })
}(window.jQuery);

(function () {
    var root = document.documentElement;
    var btn = document.getElementById('theme-toggle');

    function syncIcon() {
        btn.textContent = root.dataset.theme === 'dark' ? '☀' : '☾';
    }

    function applyTheme(theme) {
        root.dataset.theme = theme;
        try { localStorage.setItem('theme', theme); } catch (e) { }
        syncIcon();
    }

    syncIcon();

    btn.addEventListener('click', function () {
        applyTheme(root.dataset.theme === 'dark' ? 'light' : 'dark');
    });
})();

(function () {
    var card = document.getElementById('cfg-card');
    var header = document.getElementById('cfg-header');
    var collapseBtn = document.getElementById('cfg-collapse');
    var hideBtn = document.getElementById('cfg-hide');
    var restoreBtn = document.getElementById('cfg-restore');

    /* ----- Collapse / expand ----- */
    collapseBtn.addEventListener('click', function (e) {
        e.stopPropagation();
        var collapsed = card.classList.toggle('cfg-collapsed');
        collapseBtn.innerHTML = collapsed ? '&#43;' : '&#8722;';
        collapseBtn.title = collapsed ? 'Expand' : 'Collapse';
    });

    /* ----- Hide / restore ----- */
    hideBtn.addEventListener('click', function (e) {
        e.stopPropagation();
        card.style.display = 'none';
        restoreBtn.style.display = 'inline-flex';
    });
    restoreBtn.addEventListener('click', function () {
        card.style.display = '';
        restoreBtn.style.display = 'none';
    });

    /* ----- Drag ----- */
    var dragging = false, startX = 0, startY = 0, startLeft = 0, startTop = 0;

    header.addEventListener('mousedown', function (e) {
        if (e.target === collapseBtn || e.target === hideBtn) return;
        dragging = true;
        var rect = card.getBoundingClientRect();
        // switch from right/auto anchoring to explicit left/top
        card.style.left = rect.left + 'px';
        card.style.top = rect.top + 'px';
        card.style.right = 'auto';
        startX = e.clientX;
        startY = e.clientY;
        startLeft = rect.left;
        startTop = rect.top;
        document.body.style.userSelect = 'none';
        e.preventDefault();
    });

    document.addEventListener('mousemove', function (e) {
        if (!dragging) return;
        var nx = startLeft + (e.clientX - startX);
        var ny = startTop + (e.clientY - startY);
        nx = Math.max(0, Math.min(nx, window.innerWidth - card.offsetWidth));
        ny = Math.max(0, Math.min(ny, window.innerHeight - card.offsetHeight));
        card.style.left = nx + 'px';
        card.style.top = ny + 'px';
    });

    document.addEventListener('mouseup', function () {
        if (dragging) {
            dragging = false;
            document.body.style.userSelect = '';
        }
    });
})();