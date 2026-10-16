
const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
require('dotenv').config();

const { getConnection } = require('./database');
const oracledb = require('oracledb');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// ========================================
// PENYIMPANAN SEMENTARA
// ========================================

// Token login: token -> data user
const activeSessions = new Map();

// Lokasi agen aktif: STAMBUK -> data lokasi
const activeAgents = new Map();

// ========================================
// ROLE / HAK AKSES
// ========================================

const ROLE_LEVELS = {
    HEAD_MARKETING: '1',
    HEAD_AGENT: '2',
    AGENT: '3',
};

function resolveAppRole(levelUser) {
    const level = String(levelUser ?? '').trim();

    switch (level) {
        case ROLE_LEVELS.HEAD_MARKETING:
            return 'HEAD_MARKETING';
        case ROLE_LEVELS.HEAD_AGENT:
            return 'HEAD_AGENT';
        case ROLE_LEVELS.AGENT:
            return 'AGENT';
        default:
            return 'UNKNOWN';
    }
}

function requireRoles(...allowedRoles) {
    return (req, res, next) => {
        const role = resolveAppRole(req.authUser?.LEVEL_USER);

        if (!allowedRoles.includes(role)) {
            return res.status(403).json({
                success: false,
                message: 'Anda tidak memiliki akses ke fitur ini',
                appRole: role,
            });
        }

        req.authRole = role;
        next();
    };
}

function requireLeadership(req, res, next) {
    return requireRoles(
        'HEAD_MARKETING',
        'HEAD_AGENT'
    )(req, res, next);
}

// ========================================
// AUTHENTICATION
// ========================================

function authenticate(req, res, next) {
    const authorization = req.headers.authorization;

    if (
        !authorization ||
        !authorization.startsWith('Bearer ')
    ) {
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
            message: 'Stambuk dan password wajib diisi',
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
                message: 'Stambuk atau password salah',
            });
        }

        const user = result.rows[0];

        if (Number(user.AKTIF) !== 1) {
            return res.status(403).json({
                success: false,
                message: 'Akun tidak aktif',
            });
        }

        const appRole = resolveAppRole(user.LEVEL_USER);

        if (appRole === 'UNKNOWN') {
            return res.status(403).json({
                success: false,
                message:
                    'LEVEL_USER belum dikenali. Hubungi administrator.',
            });
        }

        const token = crypto.randomBytes(32).toString('hex');

        // Simpan data user asli di sesi.
        activeSessions.set(token, user);

        return res.json({
            success: true,
            message: 'Login berhasil',
            token,
            user: {
                ...user,
                APP_ROLE: appRole,
            },
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
// PROFIL PENGGUNA LOGIN
// ========================================

app.get('/api/auth/me', authenticate, (req, res) => {
    const appRole = resolveAppRole(req.authUser.LEVEL_USER);

    return res.json({
        success: true,
        user: {
            ...req.authUser,
            APP_ROLE: appRole,
        },
        permissions: {
            viewAllBranches: appRole === 'HEAD_MARKETING',
            viewBranchAgents: [
                'HEAD_MARKETING',
                'HEAD_AGENT',
            ].includes(appRole),
            manageOwnTasks: appRole === 'AGENT',
        },
    });
});

// ========================================
// LOGOUT
// ========================================

app.post('/api/logout', authenticate, (req, res) => {
    const token = req.headers.authorization.slice(7);

    activeSessions.delete(token);

    return res.json({
        success: true,
        message: 'Logout berhasil',
    });
});

// ========================================
// DAFTAR KANTOR
// Catatan: endpoint ini masih untuk kompatibilitas
// dengan homepage lama. Pembatasan akses perlu
// diselaraskan dengan navigasi Flutter berikutnya.
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

app.get(
    '/api/agents',
    authenticate,
    requireLeadership,
    async (req, res) => {
        let connection;

        try {
            const requestedBranch = req.query.kantor
                ? String(req.query.kantor).trim()
                : null;

            let branch = requestedBranch;

            if (req.authRole === 'HEAD_AGENT') {
                // Kepala Agen tidak boleh memilih cabang lain.
                branch = String(req.authUser.KANTOR ?? '').trim();
            }

            if (
                req.authRole === 'HEAD_MARKETING' &&
                !branch
            ) {
                // Kepala Pemasaran boleh melihat semua cabang.
                branch = null;
            }

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
                WHERE TRIM(LEVEL_USER) = '3'
                AND (
                    :kantor IS NULL
                      OR UPPER(TRIM(KANTOR)) =
                         UPPER(TRIM(:kantor))
                  )
                ORDER BY NAMA
                `,
                { kantor: branch },
                { outFormat: oracledb.OUT_FORMAT_OBJECT }
            );

            const agents = result.rows.map(agent => {
                const tracking = activeAgents.get(
                    String(agent.STAMBUK)
                );

                return {
                    ...agent,
                    APP_ROLE: 'AGENT',
                    isTracking: Boolean(tracking),
                    latitude: tracking?.latitude ?? null,
                    longitude: tracking?.longitude ?? null,
                    lastUpdated: tracking?.lastUpdated ?? null,
                };
            });

            return res.json({
                success: true,
                total: agents.length,
                data: agents,
            });
        } catch (error) {
            console.error('Get Agents Error:', error);

            return res.status(500).json({
                success: false,
                message: 'Gagal mengambil daftar agen',
            });
        } finally {
            if (connection) {
                await connection.close().catch(console.error);
            }
        }
    }
);

// ========================================
// TRACKING: MULAI
// ========================================

app.post(
    '/api/agent-tracking/start',
    authenticate,
    requireRoles('AGENT'),
    (req, res) => {
        const user = req.authUser;
        const stambuk = String(user.STAMBUK);

        if (activeAgents.has(stambuk)) {
            return res.status(409).json({
                success: false,
                message: 'Anda sudah memulai tracking',
                data: activeAgents.get(stambuk),
            });
        }

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
            startedAt: new Date().toISOString(),
            lastUpdated: null,
        };

        activeAgents.set(stambuk, agent);

        return res.status(201).json({
            success: true,
            message: 'Tracking berhasil dimulai',
            data: agent,
        });
    }
);

// ========================================
// TRACKING: STATUS PENGGUNA
// ========================================

app.get(
    '/api/agent-tracking/status',
    authenticate,
    requireRoles('AGENT'),
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
// TRACKING: UPDATE LOKASI
// ========================================

app.post(
    '/api/agent-tracking/location',
    authenticate,
    requireRoles('AGENT'),
    (req, res) => {
        const stambuk = String(req.authUser.STAMBUK);
        const agent = activeAgents.get(stambuk);

        if (!agent) {
            return res.status(409).json({
                success: false,
                message: 'Mulai tracking terlebih dahulu',
            });
        }

        const {
            latitude,
            longitude,
            accuracy,
            speed,
        } = req.body;

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
            accuracy != null && Number.isFinite(Number(accuracy))
                ? Number(accuracy)
                : null;

        agent.speed =
            speed != null && Number.isFinite(Number(speed))
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
// TRACKING: SELESAI
// ========================================

app.post(
    '/api/agent-tracking/stop',
    authenticate,
    requireRoles('AGENT'),
    (req, res) => {
        const stambuk = String(req.authUser.STAMBUK);
        const agent = activeAgents.get(stambuk);

        if (!agent) {
            return res.status(404).json({
                success: false,
                message: 'Tidak ada tracking aktif',
            });
        }

        activeAgents.delete(stambuk);

        return res.json({
            success: true,
            message: 'Tracking berhasil dihentikan',
            stambuk,
            stoppedAt: new Date().toISOString(),
        });
    }
);

// ========================================
// TRACKING: DAFTAR AGEN AKTIF
// Kepala Pemasaran: seluruh cabang
// Kepala Agen: cabangnya sendiri
// ========================================

app.get(
    '/api/agent-tracking/agents',
    authenticate,
    requireLeadership,
    (req, res) => {
        const filterKantor = req.query.kantor
            ? String(req.query.kantor).trim().toUpperCase()
            : null;

        let agents = Array.from(activeAgents.values());

        if (req.authRole === 'HEAD_AGENT') {
            const ownBranch = String(
                req.authUser.KANTOR ?? ''
            ).trim().toUpperCase();

            agents = agents.filter(
                agent =>
                    String(agent.kantor ?? '')
                        .trim()
                        .toUpperCase() === ownBranch
            );
        } else if (filterKantor) {
            agents = agents.filter(
                agent =>
                    String(agent.kantor ?? '')
                        .trim()
                        .toUpperCase() === filterKantor
            );
        }

        // Hanya agen yang sudah mengirim koordinat.
        agents = agents.filter(
            agent =>
                agent.latitude !== null &&
                agent.longitude !== null
        );

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
    console.log('Pemetaan role LEVEL_USER:');
    console.log('1 = Kepala Pemasaran');
    console.log('2 = Kepala Agen / Agen Director');
    console.log('3 = Agen');
});
