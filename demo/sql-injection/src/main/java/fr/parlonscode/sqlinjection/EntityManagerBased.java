package fr.parlonscode.sqlinjection;

import java.util.List;

import javax.persistence.EntityManager;
import javax.persistence.Query;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

@Component
public class EntityManagerBased {

	@Autowired
	private EntityManager em;
	
	public List<Person> bindParamsQuery(String name) {
		Query query = em.createQuery("from Person where name = :name");
		query.setParameter("name", name);
		
		@SuppressWarnings("unchecked")
		List<Person> result = query.getResultList();
		return result;
	}
	
	public List<Person> concatQuery(String name) {
		Query query = em.createQuery("from Person where name = '" + name + "'");
		@SuppressWarnings("unchecked")
		List<Person> result = query.getResultList();
		return result;
	}
}
