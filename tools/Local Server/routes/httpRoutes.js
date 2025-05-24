// routes/httpRoutes.js
const express = require('express');
const router = express.Router();

// Define your HTTP routes
router.get('/', (req, res) => {
    res.send('Hello World!');
});

router.get('/about', (req, res) => {
    res.send('This is the about page');
});

module.exports = router;
