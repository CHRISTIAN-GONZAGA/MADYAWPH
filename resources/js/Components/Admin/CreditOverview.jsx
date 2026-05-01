import { useState } from 'react';
import { router } from '@inertiajs/react';
import { motion, AnimatePresence } from 'motion/react';
import axios from 'axios';
import { AlertCircle, Plus, X } from 'lucide-react';
import { formatCurrency, formatDateTime } from '../../Utils/formatters';
import { isPercentage, isPositiveNumber } from '../../Utils/validators';

export default function CreditOverview({ credits }) {
    const [showRechargeModal, setShowRechargeModal] = useState(false);
    const [rechargeAmount, setRechargeAmount] = useState('');
    const [paymentMethod, setPaymentMethod] = useState('gcash');
    const [newMarkupPercentage, setNewMarkupPercentage] = useState(String(credits?.customMarkupPercentage ?? 10));

    const safeCredits = credits ?? {
        currentCredits: 0,
        warningThreshold: 5000,
        customMarkupPercentage: 10,
        totalSpent: 0,
        transactions: [],
    };
    const isLowCredits = safeCredits.currentCredits < safeCredits.warningThreshold;

    async function handleRecharge() {
        if (!isPositiveNumber(rechargeAmount)) {
            alert('Please enter a valid amount.');
            return;
        }
        try {
            const { data } = await axios.post('/admin/credits/recharge', {
                amount: Number(rechargeAmount),
                method: paymentMethod,
            });
            if (data?.redirect_url) {
                window.location.href = data.redirect_url;
                return;
            }
            setRechargeAmount('');
            setShowRechargeModal(false);
            router.reload({ only: ['credits'] });
        } catch (error) {
            alert(error?.response?.data?.message ?? 'Recharge endpoint is unavailable or failed.');
        }
    }

    async function handleUpdateMarkup() {
        if (!isPercentage(newMarkupPercentage)) {
            alert('Please enter a percentage between 0 and 100.');
            return;
        }
        try {
            await axios.patch('/admin/credits/markup', { percentage: Number(newMarkupPercentage) });
            router.reload({ only: ['credits'] });
        } catch (_error) {
            alert('Markup update endpoint is unavailable or failed.');
        }
    }

    return (
        <div className="space-y-6">
            {isLowCredits && (
                <div className="bg-destructive/10 border border-destructive/30 rounded-xl p-4 flex items-start gap-3">
                    <AlertCircle className="w-5 h-5 text-destructive mt-0.5" />
                    <div>
                        <p className="font-medium text-destructive">Low Credits Warning</p>
                        <p className="text-sm text-muted-foreground">Recharge to avoid service interruption.</p>
                    </div>
                </div>
            )}

            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                <div className="bg-primary text-primary-foreground rounded-xl p-4">
                    <p className="text-sm opacity-80">Current Balance</p>
                    <p className="font-serif text-3xl">{formatCurrency(safeCredits.currentCredits)}</p>
                    <button onClick={() => setShowRechargeModal(true)} className="mt-3 inline-flex items-center gap-1 text-sm">
                        <Plus className="w-4 h-4" /> Recharge
                    </button>
                </div>
                <div className="bg-card border border-border rounded-xl p-4">
                    <p className="text-sm text-muted-foreground">Total Spent</p>
                    <p className="font-serif text-2xl">{formatCurrency(safeCredits.totalSpent)}</p>
                </div>
                <div className="bg-card border border-border rounded-xl p-4">
                    <p className="text-sm text-muted-foreground mb-2">Commission Rate</p>
                    <div className="flex gap-2">
                        <input
                            value={newMarkupPercentage}
                            onChange={(e) => setNewMarkupPercentage(e.target.value)}
                            className="border border-border rounded-lg px-3 py-2 w-24"
                        />
                        <button onClick={handleUpdateMarkup} className="px-3 py-2 bg-secondary rounded-lg text-sm">Save</button>
                    </div>
                </div>
            </div>

            <div className="bg-card border border-border rounded-xl overflow-hidden">
                <div className="p-4 border-b border-border">
                    <h3 className="font-serif text-lg">Transaction History</h3>
                </div>
                <div className="divide-y divide-border max-h-72 overflow-auto">
                    {(safeCredits.transactions ?? []).map((transaction) => (
                        <div key={transaction.id} className="p-4 flex items-center justify-between gap-4 text-sm">
                            <div>
                                <p className="font-medium">{transaction.description ?? 'Transaction'}</p>
                                <p className="text-muted-foreground">{formatDateTime(transaction.timestamp)}</p>
                            </div>
                            <p>{formatCurrency(transaction.amount)}</p>
                        </div>
                    ))}
                    {(safeCredits.transactions ?? []).length === 0 && (
                        <p className="p-4 text-sm text-muted-foreground">No transactions yet.</p>
                    )}
                </div>
            </div>

            <AnimatePresence>
                {showRechargeModal && (
                    <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="fixed inset-0 z-50 bg-black/40 p-4 flex items-center justify-center">
                        <motion.div initial={{ scale: 0.95 }} animate={{ scale: 1 }} exit={{ scale: 0.95 }} className="w-full max-w-md bg-card rounded-2xl border border-border">
                            <div className="p-4 border-b border-border flex items-center justify-between">
                                <h4 className="font-serif text-lg">Recharge Credits</h4>
                                <button onClick={() => setShowRechargeModal(false)}><X className="w-4 h-4" /></button>
                            </div>
                            <div className="p-4 space-y-3">
                                <input
                                    type="number"
                                    value={rechargeAmount}
                                    onChange={(e) => setRechargeAmount(e.target.value)}
                                    className="w-full border border-border rounded-lg px-3 py-2"
                                    placeholder="Enter amount"
                                />
                                <select
                                    value={paymentMethod}
                                    onChange={(e) => setPaymentMethod(e.target.value)}
                                    className="w-full border border-border rounded-lg px-3 py-2 bg-input-background"
                                >
                                    <option value="gcash">GCash (PayMongo)</option>
                                    <option value="paymaya">PayMaya (PayMongo)</option>
                                </select>
                                <button onClick={handleRecharge} className="w-full bg-primary text-primary-foreground rounded-lg py-2">Confirm Recharge</button>
                            </div>
                        </motion.div>
                    </motion.div>
                )}
            </AnimatePresence>
        </div>
    );
}
