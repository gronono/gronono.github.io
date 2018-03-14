package fr.parlonscode.sqlinjection;

import java.util.List;

import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.CrudRepository;
import org.springframework.data.repository.query.Param;

public interface PersonRepository extends CrudRepository<Person, Long> {

	List<Person> findByName(@Param("name") String name);
	
	@Query("from Person where name = :name")
	List<Person> queryByName(@Param("name") String name);
}
