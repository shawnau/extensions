﻿// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

using System;
using System.Net.Http;
using System.Threading.Tasks;
using Microsoft.Extensions.Http.Resilience.Internal;
using Microsoft.Shared.Diagnostics;
using Polly;

namespace Microsoft.Extensions.Http.Resilience.Routing.Internal;

/// <summary>
/// Adds routing support to an inner strategy.
/// </summary>
public sealed class RoutingResilienceStrategy : ResilienceStrategy
{
    private readonly Func<RequestRoutingStrategy>? _provider;

    public RoutingResilienceStrategy(Func<RequestRoutingStrategy>? provider)
    {
        _provider = provider;
    }

    protected override async ValueTask<Outcome<TResult>> ExecuteCore<TResult, TState>(
        Func<ResilienceContext, TState, ValueTask<Outcome<TResult>>> callback,
        ResilienceContext context,
        TState state)
    {
        HttpRequestMessage? request = context.GetRequestMessage();

        if (request is null)
        {
            Throw.InvalidOperationException("The HTTP request message was not found in the resilience context.");
        }

        if (_provider is null)
        {
            return await callback(context, state).ConfigureAwait(context.ContinueOnCapturedContext);
        }

        using var strategy = _provider();

        // if there are not routes we cannot continue
        if (!strategy.TryGetNextRoute(out var route))
        {
            Throw.InvalidOperationException("The routing strategy did not provide any route URL on the first attempt.");
        }

        context.Properties.Set(ResilienceKeys.RoutingStrategy, strategy);

        // for primary request, use retrieved route
        request.RequestUri = request.RequestUri!.ReplaceHost(route!);

        return await callback(context, state).ConfigureAwait(context.ContinueOnCapturedContext);
    }
}
