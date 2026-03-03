<?php

use Illuminate\Support\Facades\Route;

// Route::statamic('example', 'example-view', [
//    'title' => 'Example'
// ]);

// Deep health check for external uptime monitors.
// The /up route is handled at the nginx layer (zero php-fpm cost) — use /health
// for checks that verify the volume and writable storage are actually working.
Route::get('/health', function () {
    $checks = [
        'volume_seeded'     => file_exists('/data/.seeded'),
        'content_readable'  => is_dir(base_path('content')) && is_readable(base_path('content')),
        'storage_writable'  => is_writable(storage_path('framework/cache')),
        'sessions_writable' => is_writable(storage_path('framework/sessions')),
    ];
    $failed = in_array(false, $checks, true);

    return response()->json([
        'status' => $failed ? 'degraded' : 'ok',
        'checks' => $checks,
    ], $failed ? 500 : 200);
});
