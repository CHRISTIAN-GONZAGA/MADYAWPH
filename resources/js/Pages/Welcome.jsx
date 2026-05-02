import { useEffect } from 'react';
import { router } from '@inertiajs/react';
import { motion } from 'motion/react';

export default function Welcome() {
    useEffect(() => {
        const seen = localStorage.getItem('hasSeenWelcome');
        if (seen === 'true') {
            router.visit('/auth/hotel');
            return;
        }

        const timer = setTimeout(() => {
            localStorage.setItem('hasSeenWelcome', 'true');
            router.visit('/auth/hotel');
        }, 5600);

        return () => clearTimeout(timer);
    }, []);

    return (
        <div className="min-h-screen relative overflow-hidden flex items-center justify-center" style={{ background: '#f7f5ef' }}>
            <motion.div
                className="absolute inset-0"
                style={{ background: 'linear-gradient(155deg, rgba(255,255,255,0.24), rgba(231,239,248,0.3), rgba(255,255,255,0.22))' }}
                animate={{ opacity: [0.25, 0.35, 0.28] }}
                transition={{ duration: 5.6, ease: 'easeInOut' }}
            />

            <motion.div
                className="absolute left-1/2 top-[66%] -translate-x-1/2 -translate-y-1/2 rounded-[999px]"
                style={{
                    width: '180vw',
                    maxWidth: '1200px',
                    height: '300px',
                    background: 'linear-gradient(180deg, rgba(97,148,208,0.34), rgba(57,111,177,0.5) 58%, rgba(38,83,142,0.58))',
                }}
                initial={{ scale: 2.8, y: 180, opacity: 0.95 }}
                animate={{ scale: [2.8, 1.7, 1], y: [180, 62, 0], opacity: [0.95, 0.74, 0.56] }}
                transition={{ duration: 2.5, ease: 'easeInOut' }}
            />

            <motion.div
                className="absolute inset-0"
                style={{ background: 'linear-gradient(100deg, rgba(255,255,255,0), rgba(255,255,255,0.38), rgba(255,255,255,0))' }}
                initial={{ x: '-120%' }}
                animate={{ x: ['-120%', '120%'] }}
                transition={{ duration: 1.2, delay: 0.25, ease: 'easeInOut' }}
            />

            <motion.div
                className="absolute h-[120vh] w-[22vw] max-w-[180px]"
                style={{ background: 'rgba(16,24,38,0.36)', transform: 'rotate(-8deg)' }}
                initial={{ x: '120%', opacity: 0 }}
                animate={{ x: ['120%', '-8%', '-120%'], opacity: [0, 0.52, 0] }}
                transition={{ duration: 1.1, delay: 1.55, ease: 'easeInOut' }}
            />

            <motion.div
                className="absolute inset-0"
                style={{ background: 'radial-gradient(circle at 50% 58%, rgba(170,204,240,0.24), transparent 60%)' }}
                initial={{ opacity: 0 }}
                animate={{ opacity: [0, 0.24, 0.2] }}
                transition={{ duration: 3.6, delay: 2.2, ease: 'easeInOut' }}
            />

            <div className="relative z-10 w-full flex justify-center px-4 [perspective:1200px]">
                <motion.div
                    className="w-[86vw] max-w-[390px]"
                    initial={{ scale: 1.18, y: 26, filter: 'blur(4px)' }}
                    animate={{ scale: [1.18, 1.04, 1], y: [26, 8, 0], filter: 'blur(0px)' }}
                    transition={{ duration: 3.5, delay: 1.9, ease: 'easeInOut' }}
                >
                    <MacroRevealLogo />
                </motion.div>
            </div>
        </div>
    );
}

function MacroRevealLogo() {
    return (
        <div className="relative">
            <motion.div
                className="absolute inset-0"
                style={{ background: 'radial-gradient(circle at 50% 36%, rgba(255,255,255,0.34), rgba(255,255,255,0) 58%)' }}
                initial={{ opacity: 0 }}
                animate={{ opacity: [0, 0.3, 0.2] }}
                transition={{ duration: 1.4, delay: 3.2, ease: 'easeInOut' }}
            />
            <svg viewBox="0 0 420 420" className="w-full h-auto text-[#123165]" fill="currentColor" aria-label="Madyaw logo">
                <motion.path
                    d="M92 292c68 24 174 20 248-12-48-12-84-20-130-13-52 8-88 16-118 25Z"
                    fill="rgba(12,43,86,0.45)"
                    initial={{ opacity: 0.2, y: 14, scaleX: 0.95, filter: 'blur(1.2px)' }}
                    animate={{ opacity: [0.2, 0.38, 0.22], y: [14, 10, 8], scaleX: [0.95, 1, 1], filter: 'blur(0px)' }}
                    transition={{ duration: 1.4, delay: 2.2, ease: 'easeInOut' }}
                />
                <motion.path
                    d="M78 298c72 24 186 18 272-22-42-10-72-20-120-13-61 9-92 22-152 35Z"
                    fill="#2a5fa8"
                    initial={{ opacity: 0.2, y: 16, scaleX: 0.92, filter: 'blur(1.4px)' }}
                    animate={{ opacity: [0.2, 0.74, 0.42], y: [16, 4, -1], scaleX: [0.92, 1, 1.02], filter: 'blur(0px)' }}
                    transition={{ duration: 1.3, delay: 2.1, ease: 'easeInOut' }}
                />
                <motion.path
                    d="M132 270c60-62 72-146 55-234 56 60 84 138 48 220L132 270Z"
                    initial={{ opacity: 0.12, y: 18, scaleX: 0.95, scaleY: 0.84, filter: 'blur(2px)' }}
                    animate={{ opacity: 1, y: [18, 8, 0], scaleX: [0.95, 0.98, 1], scaleY: [0.84, 0.92, 1], filter: 'blur(0px)' }}
                    transition={{ duration: 1.5, delay: 2.35, ease: 'easeInOut' }}
                />
                <motion.path
                    d="M240 268c62-67 72-156 49-248 70 66 104 153 82 252L240 268Z"
                    initial={{ opacity: 0.12, y: 12, scaleX: 0.95, scaleY: 0.84, filter: 'blur(2px)' }}
                    animate={{ opacity: 1, y: [12, 6, 0], scaleX: [0.95, 0.98, 1], scaleY: [0.84, 0.92, 1], filter: 'blur(0px)' }}
                    transition={{ duration: 1.55, delay: 2.5, ease: 'easeInOut' }}
                />
                <motion.path
                    d="M62 304l274-48 26 54H94l-32-6Z"
                    fill="rgba(22,72,132,0.8)"
                    initial={{ opacity: 0.24, y: 8, filter: 'blur(1.4px)' }}
                    animate={{ opacity: 1, y: [8, 2, 0], filter: 'blur(0px)' }}
                    transition={{ duration: 1.2, delay: 2.9, ease: 'easeInOut' }}
                />
                <motion.path
                    d="M26 338c72-20 282-16 366-6-98 17-296 15-366 6Z"
                    opacity="0.94"
                    initial={{ opacity: 0.2, x: -12, scaleX: 0.94, filter: 'blur(1px)' }}
                    animate={{ opacity: 0.9, x: 0, scaleX: 1, filter: 'blur(0px)' }}
                    transition={{ duration: 1, delay: 3.2, ease: 'easeInOut' }}
                />
            </svg>

            <motion.div
                className="absolute left-1/2 top-[64%] -translate-x-1/2 -translate-y-1/2 rounded-full border border-[#9fc4f4]/55"
                style={{ width: 210, height: 62 }}
                initial={{ opacity: 0, scale: 0.74 }}
                animate={{ opacity: [0, 0.24, 0], scale: [0.74, 1.1] }}
                transition={{ duration: 0.6, delay: 4.2, ease: 'easeInOut' }}
            />

            <motion.h1
                className="font-serif text-[#3f76b1] text-5xl sm:text-6xl tracking-[0.06em] -mt-6 sm:-mt-8"
                style={{ filter: 'blur(1.2px)', opacity: 0 }}
                initial={{ filter: 'blur(1.2px)', opacity: 0 }}
                animate={{ filter: 'blur(0px)', opacity: 1 }}
                transition={{ duration: 0.65, delay: 4.55, ease: 'easeInOut' }}
            >
                madyaw
            </motion.h1>
            <motion.p
                className="mt-1 text-[#1b2e4f] text-[11px] sm:text-sm tracking-[0.28em] sm:tracking-[0.34em] text-center"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                transition={{ duration: 0.4, delay: 4.95, ease: 'easeInOut' }}
            >
                BOOKING APP
            </motion.p>

            <motion.div
                className="absolute inset-0"
                style={{ background: 'linear-gradient(95deg, rgba(255,255,255,0), rgba(255,255,255,0.2), rgba(255,255,255,0))', transform: 'translateX(-120%)' }}
                animate={{ x: ['0%', '180%'] }}
                transition={{ duration: 0.65, delay: 5.15, ease: 'easeInOut' }}
            />
        </div>
    );
}
