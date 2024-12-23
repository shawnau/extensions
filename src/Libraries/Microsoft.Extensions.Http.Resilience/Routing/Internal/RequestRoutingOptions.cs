﻿// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

using System;

namespace Microsoft.Extensions.Http.Resilience.Routing.Internal;

public sealed class RequestRoutingOptions
{
    public Func<RequestRoutingStrategy>? RoutingStrategyProvider { get; set; }
}
