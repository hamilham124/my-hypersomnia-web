const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

// Enable CORS for all incoming requests (including your Google Site)
app.use(cors({ origin: '*' }));

// Route to deliver the master server binary
app.get('/server_list_binary', (req, res) => {
    const filePath = path.join(__dirname, 'server_list_binary');
    
    if (fs.existsSync(filePath)) {
        res.setHeader('Content-Type', 'application/octet-stream');
        res.sendFile(filePath);
    } else {
        // Fallback: Send an empty binary response if file doesn't exist yet
        res.setHeader('Content-Type', 'application/octet-stream');
        res.send(Buffer.alloc(0));
    }
});

// Basic health check endpoint
app.get('/', (req, res) => {
    res.send('Hypersomnia Master Server is running.');
});

app.listen(PORT, () => {
    console.log(`Server listening on port ${PORT}`);
});
