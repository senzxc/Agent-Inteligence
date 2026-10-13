
const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
require('dotenv').config();

const { getConnection } = require('./database');

const app = express();
const PORT = process.env.PORT || 3000;
const oracledb = require('oracledb');

app.use(cors());
app.use(express.json());

// ========================================
// PENYIMPANAN SEMENTARA (MEMORI)
// ========================================

// Token login sementara: token -> data user
const activeSessions = new Map();

// Agen yang sedang bertugas: STAMBUK -> data lokasi
const activeAgents = new Map();

// Role yang boleh memantau seluruh agen.
// Sesuaikan nilainya dengan LEVEL_USER sebenarnya di Oracle.
const TRACKING_ADMIN_LEVELS = (
    process.env.TRACKING_ADMIN_LEVELS || 'A'
)
    .split(',')
    .map(role => role.trim().toUpperCase())
    .filter(Boolean);

// ========================================
// AUTHENTICATION
// ========================================

function authenticate(req, res, next) {
    const authorization = req.headers.authorization;

    if (!authorization || !authorization.startsWith('Bearer ')) {
        return res.status(401).json({
            success: false,
            message: 'Token autentikasi wajib disertakan',
        });
    }

    const token = authorization.slice(7);
    const user = activeSessions.get(token);

    if (!user) {
        return res.status(401).json({
            success: false,
            message: 'Token tidak valid atau sesi sudah berakhir',
        });
    }

    req.authUser = user;
    next();
}

function requireTrackingAdmin(req, res, next) {
    const level = String(req.authUser.LEVEL_USER ?? '')
        .trim()
        .toUpperCase();

    if (!TRACKING_ADMIN_LEVELS.includes(level)) {
        return res.status(403).json({
            success: false,
            message: 'Akses hanya untuk admin',
        });
    }

    next();
}

// ========================================
// ROOT
// ========================================

app.get('/', (req, res) => {
    res.json({
        message: 'Agent Intelligence Tracker API',
        status: 'running',
    });
});

// ========================================
// TEST DATABASE
// ========================================

app.get('/api/test-db', async (req, res) => {
    let connection;

    try {
        connection = await getConnection();

        const result = await connection.execute(
            'SELECT * FROM DATA_USER FETCH FIRST 5 ROWS ONLY',
            {},
            { outFormat: oracledb.OUT_FORMAT_OBJECT }
        );

        return res.json({
            success: true,
            message: 'Berhasil terhubung ke Oracle',
            data: result.rows,
        });
    } catch (error) {
        console.error('Test DB Error:', error);

        return res.status(500).json({
            success: false,
            message: 'Gagal terhubung ke Oracle',
            error: error.message,
        });
    } finally {
        if (connection) {
            await connection.close().catch(console.error);
        }
    }
});

// ========================================
// LOGIN
// ========================================

app.post('/api/login', async (req, res) => {
    const { stambuk, password } = req.body;

    if (!stambuk || !password) {
        return res.status(400).json({
            success: false,
            message: 'stambuk dan password wajib diisi',
        });
    }

    let connection;

    try {
        connection = await getConnection();

        const result = await connection.execute(
            `
            SELECT
                STAMBUK,
                NAMA,
                KANTOR,
                EMAIL,
                LEVEL_USER,
                AKTIF,
                JBT,
                WARNA,
                LAYAR,
                EXPIRED
            FROM DATA_USER
            WHERE STAMBUK = :stambuk
              AND PASSWORD_USER = :password
            `,
            { stambuk, password },
            { outFormat: oracledb.OUT_FORMAT_OBJECT }
        );

        if (result.rows.length === 0) {
            return res.status(401).json({
                success: false,
                message: 'stambuk atau password salah',
            });
        }

        const user = result.rows[0];

        if (Number(user.AKTIF) !== 1) {
            return res.status(403).json({
                success: false,
                message: 'Akun tidak aktif',
            });
        }

        // Buat token sesi sementara.
        const token = crypto.randomBytes(32).toString('hex');
        activeSessions.set(token, user);

        return res.json({
            success: true,
            message: 'Login berhasil',
            token,
            user,
        });
    } catch (error) {
        console.error('Oracle Login Error:', error);

        return res.status(500).json({
            success: false,
            message: 'Terjadi kesalahan pada server',
        });
    } finally {
        if (connection) {
            await connection.close().catch(console.error);
        }
    }
});

// ========================================
// DAFTAR KANTOR
// ========================================

app.get('/api/kantor', async (req, res) => {
    let connection;

    try {
        connection = await getConnection();

        const result = await connection.execute(
            `
            SELECT
                KODE_KANTOR,
                NAMA_KANTOR,
                ALAMAT_KANTOR,
                EMAIL,
                PIC,
                KET_KANTOR,
                NO_SURAT,
                BOX,
                ZONA,
                LATITUDE,
                LONGITUDE,
                DISTANCE
            FROM DATA_KANTOR
            `,
            {},
            { outFormat: oracledb.OUT_FORMAT_OBJECT }
        );

        return res.json({
            success: true,
            message: 'Data kantor berhasil diambil',
            total: result.rows.length,
            data: result.rows,
        });
    } catch (error) {
        console.error('Oracle Kantor Error:', error);

        return res.status(500).json({
            success: false,
            message: 'Gagal mengambil data kantor',
        });
    } finally {
        if (connection) {
            await connection.close().catch(console.error);
        }
    }
});

// ========================================
// AGENT TRACKING: START
// ========================================

app.post(
    '/api/agent-tracking/start',
    authenticate,
    (req, res) => {
        const user = req.authUser;
        const stambuk = String(user.STAMBUK);

        if (activeAgents.has(stambuk)) {
            return res.status(409).json({
                success: false,
                message: 'Anda sudah memulai tugas',
                data: activeAgents.get(stambuk),
            });
        }

        const now = new Date().toISOString();

        const agent = {
            stambuk,
            nama: user.NAMA,
            kantor: user.KANTOR,
            level: user.LEVEL_USER,
            status: 'active',
            latitude: null,
            longitude: null,
            accuracy: null,
            speed: null,
            startedAt: now,
            lastUpdated: null,
        };

        activeAgents.set(stambuk, agent);

        return res.status(201).json({
            success: true,
            message: 'Berhasil mulai bertugas',
            data: agent,
        });
    }
);

// ========================================
// AGENT TRACKING: CURRENT USER STATUS
// ========================================

app.get(
    '/api/agent-tracking/status',
    authenticate,
    (req, res) => {
        const stambuk = String(req.authUser.STAMBUK);
        const agent = activeAgents.get(stambuk) ?? null;

        return res.json({
            success: true,
            active: agent !== null,
            data: agent,
        });
    }
);

// ========================================
// AGENT TRACKING: UPDATE LOCATION
// ========================================

app.post(
    '/api/agent-tracking/location',
    authenticate,
    (req, res) => {
        const stambuk = String(req.authUser.STAMBUK);
        const agent = activeAgents.get(stambuk);

        if (!agent) {
            return res.status(409).json({
                success: false,
                message: 'Mulai bertugas terlebih dahulu',
            });
        }

        const { latitude, longitude, accuracy, speed } = req.body;

        const lat = Number(latitude);
        const lng = Number(longitude);

        if (
            latitude === undefined ||
            longitude === undefined ||
            latitude === null ||
            longitude === null ||
            !Number.isFinite(lat) ||
            !Number.isFinite(lng) ||
            lat < -90 ||
            lat > 90 ||
            lng < -180 ||
            lng > 180
        ) {
            return res.status(400).json({
                success: false,
                message: 'Koordinat latitude atau longitude tidak valid',
            });
        }

        agent.latitude = lat;
        agent.longitude = lng;
        agent.accuracy =
            Number.isFinite(Number(accuracy)) && accuracy != null
                ? Number(accuracy)
                : null;
        agent.speed =
            Number.isFinite(Number(speed)) && speed != null
                ? Number(speed)
                : null;
        agent.lastUpdated = new Date().toISOString();

        activeAgents.set(stambuk, agent);

        return res.json({
            success: true,
            message: 'Lokasi berhasil diperbarui',
            data: agent,
        });
    }
);

// ========================================
// AGENT TRACKING: STOP
// ========================================

app.post(
    '/api/agent-tracking/stop',
    authenticate,
    (req, res) => {
        const stambuk = String(req.authUser.STAMBUK);
        const agent = activeAgents.get(stambuk);

        if (!agent) {
            return res.status(404).json({
                success: false,
                message: 'Tidak ada tugas aktif',
            });
        }

        activeAgents.delete(stambuk);

        return res.json({
            success: true,
            message: 'Berhasil selesai bertugas',
            stambuk,
            stoppedAt: new Date().toISOString(),
        });
    }
);

// ========================================
// AGENT TRACKING: LIST ACTIVE AGENTS
// ADMIN / SUPERVISOR ONLY
// ========================================

app.get(
    '/api/agent-tracking/agents',
    authenticate,
    requireTrackingAdmin,
    (req, res) => {
        const filterKantor = req.query.kantor
            ? String(req.query.kantor).trim().toUpperCase()
            : null;

        let agents = Array.from(activeAgents.values())
            .filter(agent =>
                agent.latitude !== null &&
                agent.longitude !== null
            );

        if (filterKantor) {
            agents = agents.filter(
                agent =>
                    String(agent.kantor ?? '')
                        .trim()
                        .toUpperCase() === filterKantor
            );
        }

        return res.json({
            success: true,
            total: agents.length,
            data: agents,
        });
    }
);

// ========================================
// START SERVER
// ========================================

app.listen(PORT, '0.0.0.0', () => {
    console.log(`Server berjalan di port ${PORT}`);
    console.log(
        'Role pemantau yang dikonfigurasi:',
        TRACKING_ADMIN_LEVELS
    );
});
