import ipaddress


def find_next_available_cidr(used_cidrs: list[str], desired_subnet_size: str, starting_cidr: str) -> str:
    """
    Trova il primo CIDR disponibile non in conflitto con quelli esistenti.

    Args:
        used_cidrs: Lista di CIDR già in uso (es. ["10.0.0.0/24", "10.0.1.0/24"])
        desired_subnet_size: Dimensione della subnet desiderata (es. "/24" o "/28")

    Returns:
        str: Il primo CIDR disponibile con la dimensione richiesta
    """
    # Converti la dimensione della subnet in un intero (es. "/24" -> 24)
    desired_prefix = int(desired_subnet_size.strip('/'))

    # Converti tutti i CIDR in uso in oggetti IPv4Network
    used_networks = [ipaddress.IPv4Network(cidr) for cidr in used_cidrs]

    # Parti da un range IP privato standard (10.0.0.0/8)
    start_network = ipaddress.IPv4Network(starting_cidr)

    # Itera attraverso tutte le possibili subnet della dimensione desiderata
    for candidate in start_network.subnets(new_prefix=desired_prefix):
        # Verifica se la subnet candidata si sovrappone con qualche rete esistente
        is_overlapping = any(
            candidate.overlaps(used_network)
            for used_network in used_networks
        )

        if not is_overlapping:
            return str(candidate)

    raise ValueError("Nessun CIDR disponibile trovato nel range specificato")
