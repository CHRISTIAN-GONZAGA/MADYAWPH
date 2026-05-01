<?php

namespace App\Http\Controllers;

use Inertia\Inertia;
use Inertia\Response;

class DashboardController extends Controller
{
    public function admin(): Response
    {
        return Inertia::render('AdminDashboard');
    }

    public function staff(): Response
    {
        return Inertia::render('StaffDashboard');
    }
}
